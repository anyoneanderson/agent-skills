# spec-inspect

Prompt-based specification quality checker for spec-generator documents.

## Overview

spec-inspect is a Claude Code skill that validates specification quality using LLM reasoning and Claude's built-in tools (Read, Write, Grep). No Python implementation required - everything runs through prompt instructions in SKILL.md.

## Features

- ✅ **Requirement ID Validation**: Ensures all referenced requirement IDs exist
- ✅ **Structure Validation**: Checks for mandatory sections
- ✅ **Contradiction Detection**: Identifies inconsistencies across documents
- ✅ **Ambiguity Detection**: Flags vague expressions
- ✅ **Markdown Reports**: Generates detailed inspection reports
- ✅ **Workflow Integration**: Seamlessly connects spec-generator → spec-inspect → spec-to-issue

## How It Works

Unlike traditional tools, spec-inspect uses **prompt engineering** instead of code:

1. **SKILL.md contains detailed instructions** for the LLM
2. **LLM reads specifications** using Read tool
3. **LLM performs checks** following step-by-step instructions
4. **LLM generates reports** using Write tool
5. **LLM suggests next actions** using AskUserQuestion

**No dependencies. No installation. No maintenance.**

## Usage

### From spec-generator Workflow

After spec-generator completes:
```
仕様書生成が完了しました。次のアクションを選択してください。
1. spec-inspectで品質チェック  👈 Select this
```

### Direct Invocation

```
User: "仕様書を検査して"
or
User: "Check spec quality for spec-inspect"
```

Claude will:
- Read the three specification files
- Run quality checks
- Generate inspection-report.md
- Display results
- Ask for next action

## Output Example

```
✅ spec-inspect 完了

📊 検査結果:
  ⛔ Critical: 1 件
  ⚠️  Warning: 2 件
  ℹ️  Info: 3 件

❌ Critical問題が見つかりました。実装前に修正が必要です。

📄 詳細レポート: .specs/my-project/inspection-report.md
```

### inspection-report.md

```markdown
# spec-inspect レポート - my-project

## 検査サマリー
- 検出問題数: **Critical: 1, Warning: 2, Info: 3**

## ⛔ Critical Issues (実装ブロッカー)

### [CRITICAL-001] 要件ID [REQ-999] が存在しない
- **ファイル**: `design.md:45`
- **詳細**: [REQ-999] は design.md で参照されているが requirement.md に定義されていません
- **修正提案**: requirement.md に [REQ-999] を追加するか、参照を修正してください
```

## Architecture

**Prompt-Driven Design**:
- No Python code
- No dependencies
- No build process
- Pure prompt engineering in SKILL.md

**Tools Used**:
- Read: Load specification files
- Write: Generate reports
- Grep: Search for patterns
- AskUserQuestion: Interactive workflow

## Checks Performed

| Check | Severity | Description |
|-------|----------|-------------|
| Requirement ID consistency | Critical | Detects references to non-existent IDs |
| Mandatory sections | Warning | Verifies standard structure |
| Contradictions | Warning | Identifies inconsistencies |
| Ambiguous expressions | Info | Flags vague terms |
| Unreferenced requirements | Info | Finds unused IDs |

## Workflow Integration

```
spec-generator → spec-inspect → spec-to-issue
   (Generate)      (Validate)      (Publish)
```

**Decision Flow**:
- ⛔ Critical issues → Fix before proceeding
- ⚠️ Warnings only → User decides
- ✅ No issues → Proceed to Issue creation

## Why Prompt-Based?

**Advantages**:
- ⚡ **Fast development**: Write instructions, not code
- 🔧 **Easy maintenance**: Edit prompts, not implementations
- 🎯 **Flexible**: Add new checks by adding instructions
- 🧠 **Smart**: Leverages LLM reasoning for nuanced checks
- 📦 **Zero dependencies**: No libraries to install or maintain

**Trade-offs**:
- Requires LLM API calls (cost)
- Slower than native code
- Results may vary slightly between runs

**Conclusion**: For specification checking, prompt-based is ideal because:
- Specification analysis benefits from LLM reasoning
- Checks change frequently (easy to update prompts)
- No performance-critical requirements

## Contributing

To add new checks:
1. Edit `SKILL.md`
2. Add check description under "ステップ3: 品質チェックの実行"
3. Define detection patterns
4. Test with sample specifications

No code changes needed!

## License

MIT
