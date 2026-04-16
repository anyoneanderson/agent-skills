# 採点基準 (rubric) プリセット集

Evaluator は毎 iteration で **採点基準 (rubric)** に従ってコードを採点する。rubric は軸の集合で、各軸は `weight ∈ {high, std, low}` と `threshold ∈ [0.0, 1.0]` を持つ。

**全軸が threshold 以上**のときのみ sprint は pass する。weight は合否判定には影響せず、**失敗報告の優先順位**にのみ影響する（高 weight の失敗が先に報告される）。

以下のプリセットは `harness-init` が `project_type` から自動選択する**出発点**である。Planner が sprint ごとの交渉で調整してよい（sprint-contract.md 参照）。

---

## Web

UI を持つプロジェクト（HTML/CSS/JS、モバイル Web、SPA 等）向け。

| 軸 | 重み | 閾値 | 説明 |
|---|---|---|---|
| Functionality | high | 1.0 | 全 acceptance scenario が E2E で pass（Playwright アクセシビリティツリー（DOM の構造的スナップショット）を画面キャプチャ比較より優先） |
| Craft | std | 0.7 | テスト存在、coding-rules.md が存在する場合は遵守（/spec-rules-init で生成、/spec 系と共有）、不在時は採点対象外、lint / 型エラーなし |
| Design | std | 0.7 | 視覚階層・余白・UX フローが product-spec の意図と整合、スコープ逸脱なし |
| Originality | low | 0.5 | AI テンプレ（Bootstrap 風の定型 UI、汎用 hero セクション等）を避け、意図を感じる実装 |

**採点メモ**:
- Functionality はほぼバイナリ。AS が 1 つでも落ちれば 1.0 未満
- Originality は主観的なので、0.7 未満を付ける時は具体的観察を 1〜2 点添える

---

## API

UI を持たず HTTP / gRPC / GraphQL 等でエンドポイントを提供するバックエンド向け。

| 軸 | 重み | 閾値 | 説明 |
|---|---|---|---|
| Functionality | high | 1.0 | 全エンドポイントシナリオが pass（contract test、ステータスコード、payload 形 |
| Craft | std | 0.7 | エラーハンドリング、入力検証、ログ、coding-rules.md が存在する場合は遵守（/spec-rules-init で生成、/spec 系と共有）、不在時は採点対象外 |
| Consistency | std | 0.7 | 命名・レスポンス封筒・エラー形式・ページネーションの一貫性 |
| Documentation | low | 0.6 | 全 public エンドポイントに OpenAPI / スキーマ / inline サンプル |

**採点メモ**:
- UI がないので "Design" の代わりに Consistency を採用
- Documentation の閾値は Web の Originality より高い（0.6）。未ドキュメント API は下流のコンシューマを積極的に壊すため

---

## CLI

人間または CI から呼ばれるコマンドラインツール向け。

| 軸 | 重み | 閾値 | 説明 |
|---|---|---|---|
| Functionality | high | 1.0 | 全ドキュメント済みコマンド・フラグが仕様どおりの終了コード・出力を返す |
| Craft | std | 0.7 | happy path + error path のテスト、coding-rules.md が存在する場合は遵守（/spec-rules-init で生成、/spec 系と共有）、不在時は採点対象外 |
| Ergonomics | std | 0.7 | help 明確、エラーが actionable、合理的デフォルト、non-TTY で予期せぬ対話プロンプトなし |
| Documentation | low | 0.6 | README に代表例、`--help` で全フラグ網羅 |

**採点メモ**:
- UI の代わりに Ergonomics。CLI の UX はフラグ・エラー・help に宿る
- non-interactive 安全性（スクリプト内の隠れた `read -p` など）は Ergonomics で評価

---

## 軸辞書（再利用可能な定義集）

Planner が交渉で独自軸を追加する時は、ここから拾うか同じ形で新規定義する。

| 軸 | 典型的 weight | デフォルト閾値 | 備考 |
|---|---|---|---|
| Functionality | high | 1.0 | ほぼバイナリ。必ず rubric の土台 |
| Craft | std | 0.7 | テスト + lint + スタイル。全プロジェクト種別で共通 |
| Design | std | 0.7 | 視覚・UX 軸。Web / モバイル専用 |
| Consistency | std | 0.7 | API の形の一貫性 |
| Ergonomics | std | 0.7 | CLI / TUI の使い勝手 |
| Documentation | low | 0.6 | README、OpenAPI、`--help` |
| Originality | low | 0.5 | AI テンプレ排除ヒューリスティック |
| Performance | low〜std | 0.6 | p95 レイテンシ、確保量、cold-start 等。sprint ごとに opt-in |
| Accessibility | std | 0.7 | a11y 準拠。Web で opt-in |
| Security | std | 0.8 | 依存 CVE、入力処理等。必要な局面で opt-in |

---

## カスタマイズガイド

交渉時に sprint 固有軸を追加すべきケース:

1. **異常に stakes が高い sprint** — migration、課金、認証等。`Security` や `Compatibility` を `threshold ≥ 0.8` で追加
2. **プリセット軸ではクリティカルなリスクを捉えきれない** — 例: 価値のほぼ全てがレイテンシにある Web sprint なら `Performance`（high、0.8）を追加、`Design` を `low` に下げる検討も
3. **軸が本当に適用不能** — 例: ユーザ向け出力ゼロの pure library CLI なら `Ergonomics` を**落とす**（threshold を 0 にしない、軸自体を外す）

ルール:
- `Functionality` は決して外さない。それなしでは sprint ではない
- `weight: high` を超える "critical" 層は harness に存在しない
- 閾値 0.5 未満はたいてい誤り。軸を外す方がほぼ正解
