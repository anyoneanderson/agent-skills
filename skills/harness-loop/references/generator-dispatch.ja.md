# Generator Dispatch（backend-aware, γ protocol）

Negotiation の各 round と Implementation の各 iteration で Generator を
呼ぶ時は、この統一 dispatch を使う。backend ごとに違うのは呼び出し方法
だけで、出力ファイル契約は共通。

併読:
[shared-state-protocol.ja.md](shared-state-protocol.ja.md)
— dispatch の入出力が従う write 権限表とファイル配置。

## backend ごとの呼び出し

有効 backend は `_state.json.effective_generator_backend` から読む
（loop の Step 1 で pin され、Step 9 sprint transition で 4 層 resolution
により再 pin される）。

### 4 層 resolution（Orchestrator 専用、ここでは読み取り情報）

`harness-loop` の Step 1 / Step 9 は以下の fallback チェーンで有効 backend を
解決する（優先度 高 → 低）:

1. `_state.json.effective_generator_backend` — runtime cache、Step 1 / Step 9
   が書き込む（本ファイルの dispatch は layer 1 のみを読む）
2. `contract.md` frontmatter `generator_backend` — Negotiation で確定した
   sprint 個別の決定値
3. `roadmap.md` `sprints[n].generator_backend` — Planner roadmap phase の
   推奨を user 確認（interactive モード）／auto-confirm（non-interactive モード）
4. `_config.yml.generator_backend` — epic 既定（常に存在）

`_config.yml.sprint_level_generator_override == false`（legacy bypass）の場合、
layers 2 と 3 は完全 skip され layer 4 のみが使われる。

resolved backend が `codex_cmux` だが `cmux` CLI が利用不可
（`command -v cmux` 失敗 または `CMUX_SOCKET_PATH` 未設定）の場合、Step 1 /
Step 9 が `claude` に fallback し、`progress.md` に WARN を追記する。

Generator dispatch（本ファイル）は layer 1 のみを読む — 4 層 resolution 自体は
Orchestrator の責務で、本ファイルの責務ではない。
`_state.json.effective_generator_backend` が欠落 / 不正なら state corruption と
みなし、user に surface し、暗黙 fallback はしない。

### `claude`

```text
Task(subagent_type="generator",
     prompt=<render 済み prompt-file の内容>)
```

Claude Code の `PostToolUse(Edit|Write)` hook が Generator の編集を
`progress.md` に逐次追記する。post-dispatch の bridge 呼び出しは、
summary 行と `_state.json` 更新を追加する。

### `codex_cli`

```bash
# impl iteration → artifact を --iter で採番
.harness/scripts/codex-cli-dispatch.sh \
  --phase impl \
  --iter "$ITER" \
  --agent "generator-codex_cli" \
  --sprint "$SPRINT" \
  --prompt-file "$PF" \
  --report-dir "$REPORT_DIR" \
  --model "$MODEL"

# negotiation round → artifact を --round で採番 (--iter ではない)
.harness/scripts/codex-cli-dispatch.sh \
  --phase negotiation \
  --round "$ROUND" \
  --iter "$ITER" \
  --agent "generator-codex_cli" \
  --sprint "$SPRINT" \
  --prompt-file "$PF" \
  --report-dir "$REPORT_DIR" \
  --model "$MODEL"
```

補足:

- `$MODEL = _config.yml.codex_generator_model`（既定 `gpt-5.4`）
- `$REPORT_DIR` = sprint の feedback ディレクトリ
- `$PHASE` = negotiation | impl
- `$ITER` = impl iteration 番号 (negotiation での `--iter` fallback 値でもある)
- `$ROUND` = negotiation round 番号。`--phase negotiation` では `--round` で
  渡し、iteration を 0 に reset しても round カウンタが汚染されないようにする。
  negotiation で `--round` を省略した場合は warning を出して `--iter` に
  fallback する (経過措置)
- `$SPRINT` = sprint 番号
- `$WS` = workspace root
- `$PF` = render 済み prompt-file のパス

同期実行する。dispatch script が
`git ls-files -m -o --exclude-standard`
を pre/post で取り、phase ごとの feedback
（`generator-neg-<round>.md` / `generator-<iter>.md`）と対応する
canonical report を書き、それを
`.harness/scripts/codex-progress-bridge.sh` に流す。

TODO: `codex exec resume` を harness-loop から実際に使う時点で、
resume strategy 用の設定キーを再導入する。

### `codex_cmux`

`cmux-delegate` は CLI 実行ファイルではなく Skill tool の entry point。
Orchestrator は次の擬似コードで dispatch する:

```text
if CMUX_SOCKET_PATH is empty:
  fail with "codex_cmux requires an active cmux session (CMUX_SOCKET_PATH)"

if skill "cmux-delegate" is unavailable:
  fail with "cmux-delegate skill is not installed; install it or switch
  _config.yml.generator_backend to claude"

Skill(
  skill="cmux-delegate",
  args="Codex CLI を新しい cmux pane に委譲して generator を実行する。 \
working directory: $WS。prompt file: $PF。expected outputs: \
$REPORT_DIR/generator-$ITER.md と $REPORT_DIR/generator-$ITER-report.json。 \
Codex が idle になった後に Orchestrator が monitor する前提で dispatch だけ行う。"
)
```

Prerequisites:

- `cmux` CLI が `PATH` 上にある
- `codex` CLI が `PATH` 上にある
- `CMUX_SOCKET_PATH` が set 済み
- `$PF` が `$WS` から解決できる

Skill の返り値は dispatch ack に過ぎず、完了シグナルではない。
Orchestrator は pane idle を完了シグナルとして待つ
（後述 §Completion signal）。

## Prompt-file の render

phase でテンプレを選ぶ:

- Negotiation round → `prompt-templates/generator-negotiation.md`
- Implementation iter → `prompt-templates/generator-implementation.md`

placeholder を置換して temp file に書く:

| Placeholder | 値 |
|---|---|
| `{{EPIC_NAME}}` | `_state.json.current_epic` |
| `{{SPRINT_NUMBER}}` | `_state.json.current_sprint` |
| `{{SPRINT_FEATURE}}` | その sprint の roadmap entry |
| `{{ROUND}}` | 現在の negotiation round (1..3) |
| `{{ITER}}` | 現在の impl iteration |
| `{{EVALUATOR_FB_PATH}}` | この sprint の最新 `evaluator-*.md` の相対パス。無ければ `(none)` |

言語は session / user 言語に合わせ、可能なら `.ja.md` variant を選ぶ。

## Completion signal（backend ごと）

Orchestrator は Generator の backend 固有 completion signal が発火するまで
Post-dispatch に入ってはならない。ファイル存在だけでは完了シグナルに
ならない。テンプレは中間書き込みを禁じるが、防御的な Orchestrator は
それでもプロセスレベルの signal を待つ。

| Backend | Signal | Detection |
|---|---|---|
| `claude` | Task tool return | `Task()` は blocking call。その return を正本とする |
| `codex_cli` | dispatch script exit + report.json 生成完了 | `.harness/scripts/codex-cli-dispatch.sh` の終了と canonical report path の生成を確認 |
| `codex_cmux` | cmux pane idle | `Working (` 行が `codex_cmux_idle_dwell_polls` 回連続で現れず、poll 間隔が `codex_cmux_idle_poll_seconds` 秒で、かつ feedback 2 ファイルが存在 |

Semantics:

- **Signal fires, files absent**: 下記ルールで blocked / fallback report を synthesize し、WARN を追記
- **Files present, signal has NOT fired**: WAIT。中間ファイルとみなし、まだ読まない
- **Signal fires, files present**: Post-dispatch に進む

既定の cmux dwell 設定は `_config.yml` に公開:

```yaml
codex_cmux_idle_dwell_polls: 2
codex_cmux_idle_poll_seconds: 20
```

## Post-dispatch（backend 非依存）

1. Generator role contract の 2 ファイルを期待する:
   - negotiation: `.../feedback/generator-neg-<round>.md` +
     `.../feedback/generator-neg-<round>-report.json`
   - implementation: `.../feedback/generator-<iter>.md` +
     `.../feedback/generator-<iter>-report.json`

2. backend=`claude` では、`Task()` が戻った直後に
   `.harness/scripts/claude-dispatch.sh --post-dispatch` を必ず実行する。
   この wrapper は subagent を起動しない。責務は path / 命名の正規化、
   期待ファイル不在時の fallback 合成、`git ls-files -m -o --exclude-standard`
   による `touchedFiles` 上書き、`progress-append.sh` 経由の WARN 出力のみ。
   `_state.json` は直接 touch しない。

   ```bash
   .harness/scripts/claude-dispatch.sh --post-dispatch \
     --phase <negotiation|impl> \
     --iter <iter> \
     --round <round> \
     --agent "generator-claude" \
     --role generator \
     --sprint <sprint-number> \
     --report-dir "<feedback-dir>" \
     --prompt-file "<rendered-prompt>"
   ```

   backend=`codex_cli` では `codex-cli-dispatch.sh` が内部で処理する。
   backend=`codex_cmux` では既存の cmux post-dispatch monitor を維持し、
   pane idle signal 後も期待ファイルが無い場合に限って fallback を合成する。

3. report を bridge に流す。runtime backend に対応する `--backend-label`
   を必ず添えて log token を一致させる:
   ```bash
   # backend = claude
   cat "<report-path>" | .harness/scripts/codex-progress-bridge.sh \
     --phase <negotiation|impl> \
     --iter <n> \
     --agent "generator-claude" \
     --backend-label "Claude" \
     [--sprint <sprint-number>]

   # backend = codex_cli (BC default; --backend-label 省略可)
   cat "<report-path>" | .harness/scripts/codex-progress-bridge.sh \
     --phase <negotiation|impl> \
     --iter <n> \
     --agent "generator-codex_cli" \
     --backend-label "Codex" \
     [--sprint <sprint-number>]
   ```

   bridge は atomically 次を行う:
   - `touchedFiles` の各項目につき `progress.md` に
     `agent=<name> | phase=<p> | <Label> | <path>` を 1 行（`<Label>` は
     `--backend-label` の値、default `Codex`）
   - `<label-lower>-done`（例: `claude-done` / `codex-done`）summary
     行を 1 行（`thread`, `files`, `status`, `summary` を含む）
   - `_state.json` を更新: `last_agent`, phase ごとの counter
     （`negotiation_round` または `iteration`）, `phase`、
     report に `codex_thread_id` がある場合（つまり Codex backend）の
     み `codex_thread_ids[sprint][neg-<round>|<iter>]` を populate

## Retry / error handling

- **Generator invocation non-zero exit**（Codex CLI が non-zero、Task tool が例外、
  cmux pane が設定 dwell 内に idle へ到達しない）:
  phase ごとの report
  （`feedback/generator-neg-<round>-report.json` または
  `feedback/generator-<iter>-report.json`）に `status: "blocked"` と
  `blocker: "<短い理由>"` を書く。Orchestrator が直接ファイル編集を補うことはしない。
  loop は Evaluator へ進み、`fail` 採点になる。
- **Report missing AND git ls-files empty**:
  Generator が実質何も残していない。空の `touchedFiles` と
  `summary: "(no changes detected)"` の fallback report を書く。
  Evaluator が機能軸で fail する。
- **Bridge exits non-zero**:
  progress.md / _state.json が壊れているか到達不能。stderr へ出し、
  安易に retry しない（無限 loop の恐れ）。人間へ surface し、
  `pending_human` 扱いにする。

## この構成にする理由

backend 非依存化のコストはこの 1 ファイルだけ。代わりに:

- 新 backend 追加（例: Gemini plugin）は呼び出し分岐を 1 節足すだけ
- `SKILL.md` 側の Orchestrator ロジックが入れ子分岐だらけにならない
- どの backend が動いたかに依らず diff review と監査が同じ形になる
