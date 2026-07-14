# spec-review リファレンスガイド

## マトリックスレビューの詳細

レビューの核心は、ルール × ファイルの体系的なクロスチェック：

```
ルール:  [RR-001, RR-002, CR-MUST-001, CR-MUST-002, ...]
ファイル: [src/auth/service.ts, src/api/routes.ts, ...]
マトリックス: ルール数 × ファイル数 のセルをチェック
```

### カテゴリマッチング

すべてのルールがすべてのファイルに適用されるわけではない：

| ルールカテゴリ | 適用対象 |
|---|---|
| security | 全ソースファイル |
| typescript | `.ts`, `.tsx` ファイル |
| testing | `*.test.*`, `*.spec.*` ファイル |
| style | 全ソースファイル |
| api | コントローラ、ルート、ハンドラファイル |
| database | ORM モデル、マイグレーション、クエリファイル |
| naming | 全ソースファイル |

### 重大度分類

| 重大度 | 例 | 読み方 |
|---|---|---|
| Critical | SQL インジェクション、秘密鍵のハードコード、NULL ポインタ、データ損失 | 人間の優先度は最上位 |
| Improvement | エラーハンドリング不足、非効率なアルゴリズム、命名不適切 | 修正に値する |
| Minor | スタイル不一致、余分な空白、コメント品質 | 記録のみ |

severity は人間の読み・優先度づけ用である。Gate で止めるかは `fix_before` タグだけで
決まる（定義・既定値 `follow_up`・格上げの立証責任は SKILL.md Step 4.5）。修正が後の
マイルストーンに属する Critical の finding があっても Gate は緑のままで、その finding
は記録して持ち越される — 黙って捨てられることはない。

## レビューファイルフォーマット

SKILL.md Step 5 の完全テンプレートを参照。要点：
- 各指摘にはファイル:行番号の参照を含める
- 各指摘にはルール ID を参照する
- Critical / Improvement の各指摘には `fix_before` タグ
  （`implementation | trial | required_check | follow_up`）を付ける
- Critical と Improvement はチェックリスト形式（`- [ ]`）（spec-code が修正追跡に使用）
- Minor はプレーンテキスト（情報のみ）

## Diff 戦略

| コンテキスト | コマンド | 備考 |
|---|---|---|
| 明示的なベース付きタスクスコープ | `git diff {base-commit}...HEAD` | オーケストレーターが `--base-commit` を渡す場合の推奨形 |
| 自動検出のタスクスコープ | `git log --oneline` でタスク開始コミットを特定、`git diff {commit}...HEAD` | 開始コミットが曖昧でない場合のみ使用 |
| ステージ済み変更 | `git diff --cached` | コミット前レビュー用 |
| ワーキングツリー | `git diff` | 未ステージの変更 |
| PR スコープ | `git diff {base}...HEAD` | PR 全体レビュー |
