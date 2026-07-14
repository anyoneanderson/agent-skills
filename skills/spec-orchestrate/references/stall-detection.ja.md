# 停滞検知と裁定

レビューループにハード上限は設けない — 難しいレビューで10往復は正常系。
避けたいのは *前進しない* ループが永久に回ることだ。このファイルは `state.rounds`
だけを見る純粋に機械的な検知器と、検知器が成立したときにのみ走る裁定を定義する。
機械がシグナルを記録し、判断は人または LLM が行う。

English version: [stall-detection.md](stall-detection.md)

## 検知器が見る findings

検知器が見るのは、修正ループが実際に対処する findings だけである:

- **spec_review ループ**: `fix_before: implementation` の finding — 修正ループが
  直すのはこれだけ。先送りの finding（`trial` / `required_check` / `follow_up`）と
  Minor は記録して持ち越すだけで修正しないため、数えるとラウンドのたびに偽の停滞を
  発火させてしまう。
- **evaluate ループ**: Critical + Improvement の findings（失敗した受け入れケースは
  すべて修正が必要なので、全件がループを駆動する）。

以下、「修正ループ対象の findings」はそれぞれのループにおけるこの集合を指す。
`pipeline.yml` で `review.fix_before_stages` を定義し直しているプロジェクトは、
本ファイルの `implementation` をその一覧の**先頭**の段階と読み替える
（`pipeline-config.ja.md` 参照）。

## findings 指紋

指紋は finding の同一性キーで、「言い換えられた同じ指摘」をラウンドをまたいで同一と
数えるためのもの。修正ループ対象の finding ごとに計算する:

```
fingerprint = sha1( req_id + "\x1f" + severity + "\x1f" + norm_path + "\x1f"
                    + section_heading + "\x1f" + gist_80 )
```

- `req_id` — finding が挙げる要件ID（例: `REQ-001`）。
- `severity` — `Critical` / `Improvement` / `Minor`。
- `norm_path` — 対象ファイルパスを正規化（リポジトリ相対、スラッシュ区切り）。
- `section_heading` — finding が対象とする設計/仕様のセクション見出し。
- `gist_80` — finding 要旨の先頭80字を **正規化**: 空白を単一スペースに圧縮し
  小文字化する。

req_id・severity・section を含めるのは意図的: ラウンド間で文言が少し変わっても同じ
指紋にハッシュされ、本当に再発している指摘を「毎回新規」に見せず検出できる。

シェル形（Linux は `sha1sum`、macOS は `shasum`。移植性のためフォールバックする）:
```bash
sha1() { sha1sum 2>/dev/null || shasum; }   # macOS は sha1sum ではなく shasum
gist_80="$(printf '%s' "$gist" | tr -s '[:space:]' ' ' | tr '[:upper:]' '[:lower:]' | cut -c1-80)"
fp="$(printf '%s\x1f%s\x1f%s\x1f%s\x1f%s' "$req_id" "$severity" "$norm_path" "$section" "$gist_80" | sha1 | cut -c1-40)"
```

## クラスキー（S4 用）

指紋は細かすぎて、「文言と行を変えて戻ってくる同じ *クラス* の欠陥」を捉えられない。
クラスキーは severity と要旨を落とし、finding が着地する場所だけを残す:

```
class_key = sha1( norm_path + "\x1f" + section_heading )
```

（指紋と同じ sha1 のシェル形。先頭40字。）

クラスキーは指紋と同じ集合、つまり**修正ループ対象の findings のみ**で計算する。
先送りの finding は持ち越され、再レビュー規則により蒸し返されない — そこで再発する
クラスはノイズになる。S4 が捉えるべきパターンは、修正ループ対象の finding が毎ラウンド
修正されながら、翌ラウンドに同じ場所へ同じクラスの別 instance が現れることである。

## 各ラウンドが記録するもの

レビュー/評価の各ラウンド終了時に、対応する `state.rounds.<loop>` 配列
（`spec_review` か `evaluate`）にエントリを1件追記する:

```json
{"round": N, "critical": c, "improvement": i, "minor": m,
 "fix_required": f, "fingerprints": ["<fp>", ...],
 "class_keys": ["<ck>", ...], "gate": "PASS|FAIL"}
```

- `fix_required` — このラウンドの修正ループ対象の finding 件数（spec_review:
  `fix_before: implementation` の件数。evaluate: `critical + improvement`）。
- `fingerprints` — 修正ループ対象の findings のみ。Minor と先送りの finding は
  除外する: これらは設計上ラウンドをまたいで残り続けるため、数件残るだけで S1 を
  毎回誤発火させてしまう。
- `class_keys` — 修正ループ対象の findings のみ（ソート・重複除去）。

検知器はこの配列 **だけ** を読む — finding 本文も再パースもしない。これがシグナルを
state だけから再現可能にする。

**旧形式のラウンド。** この契約より前に記録されたエントリには `fix_required` と
`class_keys` が無い。それを理由に resume を止めないこと: そのラウンドの
`fix_required` は `critical + improvement` として導出し、`class_keys` の無い
ラウンドを含む3ラウンド窓では S4 を評価不能として扱う。

## シグナル（各ラウンド終了時に評価）

ループのラウンドを順に `r[1..N]`、`set(k)` = ラウンド `k` の指紋集合（ソート・重複
除去）、`classes(k)` = ラウンド `k` のクラスキー集合、`total(k) = fix_required(k)`
とする。

- **S1 — 再発する finding。** ある指紋が直近3ラウンド連続で存在:
  `∃ fp ∈ set(N) ∩ set(N-1) ∩ set(N-2)`。N ≥ 3 が必要。
- **S2 — 作業量が非減少。** 修正ループが作業量を減らせていない:
  `total(N-2) ≤ total(N-1) ≤ total(N)`。N ≥ 3 が必要。`total` が数えるのは
  修正ループ対象の findings — ループが燃やし切るべき残作業。
- **S3 — 振動。** 指紋集合が2状態を交互に取る:
  `set(N) == set(N-2)` かつ `set(N) ≠ set(N-1)`（A→B→A→B パターン）。N ≥ 3 が必要。
  4ラウンド目が同パターンなら確証。
- **S4 — 同型クラスの反復。** あるクラスキーが直近3ラウンド連続で存在:
  `∃ ck ∈ classes(N) ∩ classes(N-1) ∩ classes(N-2)`。N ≥ 3 が必要。S1 が成立
  しなかったときだけ評価する（S1 のほうが強い・厳密な形であるため）。S4 は S1 が
  捉えられないものを捉える: 個々の instance は毎回修正されるので指紋は再発しないが、
  翌ラウンドに同じ場所で同じクラスの別 instance が現れる — 個別パッチを何度繰り返しても
  指摘が尽きない状態である。

S1/S2/S3/S4 のいずれかが成立したら `phase = arbitration` にし、どのシグナルが成立
したか記録する。そうでなければ通常の修正ループを続ける。

## 裁定

裁定はシグナル成立後にのみ走る。判断材料:

- ラウンド推移表（`state.rounds` から）、
- このラウンドで未解決の findings 本文、
- 直近で試みた修正。

### S4 は裁定が異なる: 構造変更を指令する

S4 の意味は「finding 単位のパッチでは収束しない」— 設計が、ループが直すのと同じ速さで
同じクラスの新しい instance を生んでいる。レビュアーの入れ替えは効かない（個々の指摘は
正しい）。変えるべきは設計である。

S4 では、他のどの分岐よりも先に、**planner への構造変更の指令**を出す（1ループにつき
最大1回）: 停滞したループの修正フェーズ（spec_generate または implement）へ、次の指示と
ともに差し戻す — 「個別の finding へのパッチをやめよ。このクラスの欠陥が構造的に発生
しない設計に作り直せ: それを不可能にする不変条件を定義し、実装とテストに守らせよ」。
`decision: "restructure"` として記録する。入れ替え予算は消費しない。このループで既に
構造変更の指令を出した後に S4 が再度成立した場合は、下の通常分岐へ進む。

### manual

AskUserQuestion で人に尋ねる（バイリンガル文言必須）:

```
question: "The review loop appears stalled ({signal}). How should it proceed?" /
          "レビューループが停滞しています（{signal}）。どう進めますか？"
options:
  - "Continue the loop" / "ループを続行"
  - "Order a structural redesign" / "構造の再設計を指令する"
  - "Change approach (I'll give instructions)" / "方針変更（指示を入力する）"
  - "I'll take it over" / "人間が引き取る"
```

- 続行 → ループのフェーズに戻る。
- 構造の再設計 → 上記の planner への指令を出して続行する。
- 方針変更 → 人の指示を planner/実装者に修正指令として渡し、続行する。
- 引き取る → state を保持して停止。以降は人が運転する。

### auto

人がいないので自律的に選ぶ（上記の S4 規則を先に適用した後）:

1. **(a) 担当を入れ替える** — 停滞したフェーズ/タスクの担当を反対側 LLM に入れ替えて
   続行する。ただし入れ替え予算がある場合のみ: 最大 `limits.role_swap_max` 回
   （既定1）。新しい担当を `state.role_overrides` に記録する。
   （例: codex レビュアーでは指摘件数が減らない spec-review を claude レビュアーで
   再実行する）。
2. **(b) draft PR で着地する。** 入れ替え予算を使い切っている（既に1回入れ替え済み）
   なら (a) は使えず、未解決の修正ループ対象 findings を記録した **draft PR** で
   着地する（PR 組み立ては pr.md）。

つまり auto の最初の停滞は1回入れ替え、（入れ替え後の）2度目の停滞で draft 着地する。

### 裁定の遷移

- 続行 / 担当入れ替え後 / 構造変更の指令後 → 停滞した側の **spec_review** または
  **implement** に戻る。
- draft PR 着地 → **pr**（PR は draft で作成）。

## 裁定の記録

すべての裁定を state に書き、人に見えるようにする:

1. `state.arbitrations` に追記:
   ```json
   {"phase": "spec_review", "signal": "S1", "decision": "continue|swap|restructure|draft",
    "note": "...", "ts": "<ISO 8601>"}
   ```
2. 人が見る場所に転記する:
   - auto で Issue 起点 → `gh issue comment <N>` にシグナルと裁定を書く。
   - それ以外 → PR 本文（`## Unresolved` / レビュー履歴セクション）。

黙って解決された停滞はバグ: この記録があるからレビュアーは、なぜ担当が入れ替わったか
/ なぜ draft で着地したかを理解できる。
