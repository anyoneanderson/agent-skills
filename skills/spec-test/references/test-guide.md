# spec-test Reference Guide

## Test Framework Detection

Scan these locations to detect the test framework:

| File/Config | Framework |
|---|---|
| `jest.config.*` or `package.json` has `"jest"` | Jest |
| `vitest.config.*` or `package.json` has `"vitest"` | Vitest |
| `.mocharc.*` | Mocha |
| `pytest.ini` / `pyproject.toml` has `[tool.pytest]` | pytest |
| `go.mod` exists | Go test (`go test ./...`) |
| `Cargo.toml` exists | Rust test (`cargo test`) |
| `Gemfile` has `rspec` | RSpec |

## Test Command Detection

Priority order:
1. `coding-rules.md` test section
2. `CLAUDE.md` test commands
3. `package.json` scripts: `test`, `test:unit`, `test:integration`
4. Framework defaults (see above)

## Test Result File Format

See SKILL.md Step 6 for the full template. Key fields:
- `Tests: {passed}/{total}` — must show counts
- `Coverage: {percentage}%` — if coverage tool available
- `Completion Criteria Coverage` table — maps each task criterion to a test
- `Gate: PASS / FAIL` — binary, based on all tests passing

## AAA Pattern

All tests should follow Arrange-Act-Assert:

```typescript
it('should deactivate child DIDs when parent is deactivated', async () => {
  // Arrange
  const parentDid = await createTestDid({ status: 'active' });
  const childDid = await createTestDid({ parentDidId: parentDid.id, status: 'active' });

  // Act
  await service.deactivateDidWeb(parentDid.identifier);

  // Assert
  const updatedChild = await prisma.did.findUnique({ where: { id: childDid.id } });
  expect(updatedChild.status).toBe('deactivated');
});
```
