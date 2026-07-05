# 結果ファイル形式 — evaluate-{round}.md

evaluator はラウンドごとに結果ファイルを1つ書く:
`.specs/{feature}/evaluate-{round}.md`。役割は2つ。(1) `spec-code --feedback` が
変換なしで受け取れること、(2) ディスク上の証跡に対して独立に検証可能であること。

(1) のため、**spec-review と同じ Findings 構造**を使う（`type` ヘッダ、
`### Critical` / `### Improvement` / `### Minor` を持つ `## Findings`、`Gate:`
行を持つ `## Summary`）。不合格の受け入れ項目は **Critical** に、懸念・劣化は
**Improvement** に対応づける。(2) のため、PASS の各行は実在必須の証跡ファイルを
相対ポインタで示す。

## 形式

```markdown
# 受け入れ評価: {feature} — round {n}
type: evaluate

## Meta
- Evaluator: spec-evaluate ({backend})
- Date: {ISO 8601}
- Test plan: .specs/{feature}/test.md
- Evidence dir: .specs/{feature}/evidence/{n}/
- App recipe: {present | absent}

## Requirement Results
| Case | Requirement | Verify | Verdict | Evidence |
|------|-------------|--------|---------|----------|
| T-A01 | REQ-001 | playwright | PASS | evidence/{n}/T-A01-login.png |
| T-A02 | NFR-001 | command | FAIL | evidence/{n}/T-A02-latency.log |
| T-A03 | REQ-005 | file-check | PASS | evidence/{n}/T-A03-export.log |
| T-A04 | REQ-007 | playwright | BLOCKED | evidence/{n}/app-startup.log |

## Findings

### Critical
- [ ] **T-A02 [NFR-001]** `evidence/{n}/T-A02-latency.log` — p95 レイテンシ
  820ms が 500ms 要件を超過。期待 p95 < 500ms、実測 820ms。

### Improvement
- [ ] **T-A01 [REQ-001]** ログインは成功するが、データ読み込み前に約1秒
  空状態が表示される。判定は合格だが改善の余地あり。

### Minor
- （なし）

## Blocked
- **T-A04 [REQ-007]** アプリ起動レシピが利用不可 — pipeline.yml に `app:`
  セクションがない。証跡: `evidence/{n}/app-startup.log`。不合格には数えない。
  実行には起動レシピが必要。

## Summary
- Cases: 2 PASS / 1 FAIL / 1 BLOCKED (4 total)
- Critical: 1 | Improvement: 1 | Minor: 0
- Gate: FAIL
```

## フィールド規則

- `type: evaluate` ヘッダは必須（`type: review` / `type: test` に倣う）。
- **Requirement Results** 表: 1行1項目で、項目ID・要件ID・検証方法・判定・証跡
  ポインタを持つ。パイプラインが読む要件別の合否ビュー。
- 判定は `PASS | FAIL | BLOCKED` のいずれか。
- **Evidence** 列は `.specs/{feature}/` からの相対ポインタ。PASS の行で、実在
  かつ非空のファイルに解決できないポインタは不正。
- **Findings** の各セクションは spec-review と完全に一致させ、
  `spec-code --feedback` が特別扱いなしにパースできるようにする。各
  Critical/Improvement 項目は項目IDと要件IDを明示する。
- **Blocked** セクションは準備不足で実行できなかった項目を列挙する。blocked は
  FAIL と区別する: Critical finding ではなく、実装の品質欠陥でもない。

## Gate 論理

- FAIL 項目が1つでもあれば `Gate: FAIL`（Critical finding あり）。
- FAIL はないが BLOCKED があれば、blocked 項目を理由になお `Gate: FAIL`。無人
  実行で未検証の UI 要件を受け入れ済みとして扱わせない。
- 全項目 PASS のとき `Gate: PASS`。

## 機械検証（evaluator ではなく runner が強制）

evaluator が戻った後、spec-evaluate は書かれたファイルを再チェックする:

1. 判定 PASS の各行について、Evidence ポインタを `.specs/{feature}/` 基準で
   解決する。
2. ファイルが欠落・空なら判定を FAIL に書き換え、Critical finding を追加する:
   「evidence not found for {case}: {pointer}」。
3. `## Summary` の集計と `Gate:` 行を再計算する。

これが NFR-003 の裏づけ: 証跡のない自己申告の合格は、受理された結果まで生き残れ
ない。

## spec-code へのフィードバック

Critical と Improvement の findings はそのまま `spec-code --feedback` に渡す。
builder がそれらを修正し、implement ⇄ evaluate ループが `round + 1` で回る。
形式が spec-review と一致しているため、受け入れ層と実装ループの間にアダプタは
不要。
