# Agentとpipelineの設定

workflow生成後にStep 6aからStep 6dを実行する。

## Step 6a：Claude Code agent

Round 7がClaudeを含む場合、入力言語に対応する`references/agents/claude/workflow-*` templateを読む。coding rules path、workflow path、test、lint、typecheck、build、E2E、browser E2E、coverage command、開発style、branch namingのplaceholderを置換する。各agentが現在または既定のmodelを継承できるよう、`model`は設定しない。

`.claude/agents/`を作り、`workflow-implementer.md`、`workflow-reviewer.md`、`workflow-tester.md`、`workflow-planner.md`、`workflow-evaluator.md`を書く。plannerはspecとtest.mdを生成し、evaluatorは受入テストを実行する。`--force`指定時を除き、既存fileを上書きする前に確認する。

## Step 6b：Codex agent

Round 7がCodexを含む場合、対応する`references/agents/codex/workflow-*` TOML templateを読み、`developer_instructions`内の同じplaceholderを置換する。`model`と`model_reasoning_effort`は設定しない。

`.codex/agents/`を作り、`workflow-implementer.toml`、`workflow-reviewer.toml`、`workflow-tester.toml`、`workflow-planner.toml`、`workflow-evaluator.toml`を書く。`--force`指定時を除き、上書き前に確認する。`.codex/config.toml`を作成またはmergeし、無関係な設定を保ったまま`[agents] max_threads = 3`、`max_depth = 1`、`[features] multi_agent = true`を設定する。custom agentは`.codex/agents/*.toml`から見つかるため、`[agents.<name>] config_file`は追加しない。

## Step 6c：Pipeline config

入力言語に応じて`pipeline-yml-template.md`または`pipeline-yml-template.ja.md`を読む。`.specs/pipeline.yml`があればpathを報告して上書きしない。なければ`.specs/`を作り、選択したtemplateをそのまま書く。

## Step 6d：Watchdog Stop hook

実行中のpipelineがphase境界で黙って停止しないよう、spec-orchestrate watchdogを登録する。

1. `.claude/skills/spec-orchestrate/references/scripts/pipeline-watchdog.sh`がなければ報告して飛ばす。
2. `.claude/settings.json`に`pipeline-watchdog.sh`があれば、登録済みのpathを報告して飛ばす。
3. それ以外では、次の契約でAskUserQuestionを使う。

   - question: `Register the spec-orchestrate watchdog Stop hook in .claude/settings.json?` / `.claude/settings.json に spec-orchestrate の watchdog Stop hook を登録しますか？`
   - header: `Watchdog`
   - options: `Yes, register (Recommended)` / `はい、登録する（推奨）`; `No, skip` / `いいえ、スキップ`
4. 承認時はfileまたは不足するarrayを作り、既存entryを保ったまま次のshapeを`hooks.Stop`へmergeする。

   ```json
   {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash .claude/skills/spec-orchestrate/references/scripts/pipeline-watchdog.sh"}]}]}}
   ```

新しい`.specs/.orchestrate-active.json` markerがなければ、このhookは停止を常に許可する。
