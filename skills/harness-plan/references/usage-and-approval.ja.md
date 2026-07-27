# 使用方法とroadmap承認

harness-planの引数を解釈する前に、このreferenceを読む。

## コマンド

```text
/harness-plan
/harness-plan --epic-name auth-suite --epic 142
/harness-plan --replan
/harness-plan --auto-approve-roadmap
```

最初のコマンドは、新しいepicを開始するか、永続stateから中断したdraftを再開する。`--epic 142`は親Issue 142を記録する。`--replan`は既存のproduct-spec.mdを入力としてStep 5へ戻る。

## Roadmapの自動承認

`--auto-approve-roadmap`は、harness-planの対話checkpointを自動判断へ変える唯一の仕組みである。`_config.yml`や後続のharness-loop modeから自動実行を推測しない。

このflagを一つの設定として、すべてのcheckpointへ適用する。

| Checkpoint | 既定 | flag指定時 |
|---|---|---|
| Boot Sequence：resume | AskUserQuestionで確認 | `_state.json.phase`から再開 |
| Step 1：既存epic | 続行、新規、中止を確認 | stateがあれば続行し、なければ名前を導出 |
| Step 2：epic名の衝突 | 再質問 | `-N`を追加 |
| Step 4：product-spec照合が`no` | sectionを再度開く | progress.mdへ`TODO(product-spec):`を追記して続行 |
| Step 5：sprintが6件を超える | 停止 | 切り詰めてprogress.mdへ`TODO(epic-split)`を追記 |
| Step 5：Issue重複が曖昧 | AskUserQuestionで確認 | progress.mdへ`TODO(issue-dup):`を追記してsprintを除外 |
| Step 6：roadmap承認 | 承認、修正、中止を確認 | 承認してprogress.mdへ監査行を追記 |

利用者はskill完了前にroadmap.mdを確認する責任を負う。harness-loop開始前にprogress.mdの`TODO(...)`をすべて解消する。1回の呼び出しはflagを持つか持たないかのどちらかであり、途中で切り替えない。skill開始時に`[<ts>] harness-plan: --auto-approve-roadmap enabled`を正確に1回だけ記録する。
