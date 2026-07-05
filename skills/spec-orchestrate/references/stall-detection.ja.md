# 停滞検知と裁定

レビューループにハード上限は設けない — 難しいレビューで10往復は正常系（design §7）。
避けたいのは *前進しない* ループが永久に回ることだ。このファイルは `state.rounds`
だけを見る純粋に機械的な検知器と、検知器が成立したときにのみ走る裁定を定義する。
機械がシグナルを記録し、判断は人または LLM が行う。

English version: [stall-detection.md](stall-detection.md)

## findings 指紋

指紋は finding の同一性キーで、「言い換えられた同じ指摘」をラウンドをまたいで同一と
数えるためのもの。finding ごとに計算する:

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

シェル形:
```bash
gist_80="$(printf '%s' "$gist" | tr -s '[:space:]' ' ' | tr '[:upper:]' '[:lower:]' | cut -c1-80)"
fp="$(printf '%s\x1f%s\x1f%s\x1f%s\x1f%s' "$req_id" "$severity" "$norm_path" "$section" "$gist_80" | sha1sum | cut -c1-40)"
```

## 各ラウンドが記録するもの

レビュー/評価の各ラウンド終了時に、対応する `state.rounds.<loop>` 配列
（`spec_review` か `evaluate`）にエントリを1件追記する:

```json
{"round": N, "critical": c, "improvement": i, "minor": m,
 "fingerprints": ["<fp>", ...], "gate": "PASS|FAIL"}
```

検知器はこの配列 **だけ** を読む — finding 本文も再パースもしない。これがシグナルを
state だけから再現可能にする。

## シグナル（各ラウンド終了時に評価）

ループのラウンドを順に `r[1..N]`、`set(k)` = ラウンド `k` の指紋集合（ソート・重複
除去）、`total(k) = critical(k) + improvement(k)` とする。

- **S1 — 再発する finding。** ある指紋が直近3ラウンド連続で存在:
  `∃ fp ∈ set(N) ∩ set(N-1) ∩ set(N-2)`。N ≥ 3 が必要。
- **S2 — severity 非減少。** 修正ループが作業量を減らせていない:
  `total(N-2) ≤ total(N-1) ≤ total(N)`。N ≥ 3 が必要。Critical **と**
  Improvement を合算するのは修正ループが両方を対象とするため。Critical だけを見ると
  減らない Improvement の滞留を見逃す。
- **S3 — 振動。** 指紋集合が2状態を交互に取る:
  `set(N) == set(N-2)` かつ `set(N) ≠ set(N-1)`（A→B→A→B パターン）。N ≥ 3 が必要。
  4ラウンド目が同パターンなら確証。

S1/S2/S3 のいずれかが成立したら `phase = arbitration` にし、どのシグナルが成立したか
記録する。そうでなければ通常の修正ループを続ける。

## 裁定

裁定はシグナル成立後にのみ走る。判断材料:

- ラウンド推移表（`state.rounds` から）、
- このラウンドで未解決の findings 本文、
- 直近で試みた修正。

### manual

AskUserQuestion で人に尋ねる（バイリンガル文言必須）:

```
question: "The review loop appears stalled ({signal}). How should it proceed?" /
          "レビューループが停滞しています（{signal}）。どう進めますか？"
options:
  - "Continue the loop" / "ループを続行"
  - "Change approach (I'll give instructions)" / "方針変更（指示を入力する）"
  - "I'll take it over" / "人間が引き取る"
```

- 続行 → ループのフェーズに戻る。
- 方針変更 → 人の指示を planner/実装者に修正指令として渡し、続行する。
- 引き取る → state を保持して停止。以降は人が運転する。

### auto

人がいないので自律的に選ぶ:

1. **(a) 担当を入れ替える** — 停滞したフェーズ/タスクの担当を反対側 LLM に入れ替えて
   続行する。ただし入れ替え予算がある場合のみ: 最大 `limits.role_swap_max` 回
   （既定1）。新しい担当を `state.role_overrides` に記録する。
   （例: codex レビュアーが収束させられない spec-review を claude レビュアーで再実行）。
2. **(b) draft PR で着地する。** 入れ替え予算を使い切っている（既に1回入れ替え済み）
   なら (a) は使えず、未解決の Critical / Improvement を記録した **draft PR** で
   着地する（design §4.6、PR 組み立ては pr.md）。

つまり auto の最初の停滞は1回入れ替え、（入れ替え後の）2度目の停滞で draft 着地する。

### 裁定の遷移

- 続行 / 担当入れ替え後 → 停滞した側の **spec_review** または **implement** に戻る。
- draft PR 着地 → **pr**（PR は draft で作成）。

## 裁定の記録

すべての裁定を state に書き、人に見えるようにする:

1. `state.arbitrations` に追記:
   ```json
   {"phase": "spec_review", "signal": "S1", "decision": "continue|swap|draft",
    "note": "...", "ts": "<ISO 8601>"}
   ```
2. 人が見る場所に転記する:
   - auto で Issue 起点 → `gh issue comment <N>` にシグナルと裁定を書く。
   - それ以外 → PR 本文（`## Unresolved` / レビュー履歴セクション）。

黙って解決された停滞はバグ: この記録があるからレビュアーは、なぜ担当が入れ替わったか
/ なぜ draft で着地したかを理解できる。
