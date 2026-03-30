# spec-test リファレンスガイド

## テストフレームワーク検出

以下の場所をスキャンしてテストフレームワークを検出する：

| ファイル/設定 | フレームワーク |
|---|---|
| `jest.config.*` または `package.json` に `"jest"` | Jest |
| `vitest.config.*` または `package.json` に `"vitest"` | Vitest |
| `.mocharc.*` | Mocha |
| `pytest.ini` / `pyproject.toml` に `[tool.pytest]` | pytest |
| `go.mod` が存在 | Go test (`go test ./...`) |
| `Cargo.toml` が存在 | Rust test (`cargo test`) |
| `Gemfile` に `rspec` | RSpec |

## テストコマンド検出

優先順位：
1. `coding-rules.md` のテストセクション
2. `CLAUDE.md` のテストコマンド
3. `package.json` スクリプト: `test`, `test:unit`, `test:integration`
4. フレームワークデフォルト（上記参照）

## テスト結果ファイルフォーマット

SKILL.md Step 6 の完全テンプレートを参照。主要フィールド：
- `Tests: {passed}/{total}` — 件数を表示
- `Coverage: {percentage}%` — カバレッジツールがあれば
- `Completion Criteria Coverage` テーブル — タスク完了条件とテストの対応
- `Gate: PASS / FAIL` — 全テストパスでPASS

## AAA パターン

すべてのテストは Arrange-Act-Assert に従う：

```typescript
it('親DID無効化時に子DIDも無効化されること', async () => {
  // Arrange（準備）
  const parentDid = await createTestDid({ status: 'active' });
  const childDid = await createTestDid({ parentDidId: parentDid.id, status: 'active' });

  // Act（実行）
  await service.deactivateDidWeb(parentDid.identifier);

  // Assert（検証）
  const updatedChild = await prisma.did.findUnique({ where: { id: childDid.id } });
  expect(updatedChild.status).toBe('deactivated');
});
```
