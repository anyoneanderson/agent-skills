# 完了処理とsprint遷移

sprintが終端checkpointへ到達した後、以下のstepを実行する。

## Step 8：Pull Request作成

`pr-creation-guide.ja.md`を最後まで読む。`contract.status == "done"`の場合、次を実行する。

1. commitが`harness/<epic>/sprint-<n>-<feature>`にあることを確認する。
2. `tracker == none`でなければ`git push -u origin <branch>`を実行する。
3. `bundling: split`ではsprintごとにPRを作り、`bundled`では同梱する全機能を記載したPRを1件作る。
4. guideのtemplateから本文を作り、`shared_state.md/Evaluation`を引用し、`_state.json.sprint_issues[<n>]`をlinkする。
5. PR URLを`_state.json.sprint_prs[<n>]`へ保存し、progress.mdへ追記する。

abort時はPRを作らず、判断をshared_state.mdとprogress.mdへ記録し、branchを調査用に残す。

## Step 9：Sprint遷移

`aborted_reason`がnullでなければ停止し、理由を表示し、`current_sprint`を進めない。

roadmapに次のsprintがある場合、次を実行する。

1. `current_sprint`を増やし、`iteration = 0`、`phase = "negotiation"`とする。
2. `start_time`を現在時刻へ、`rubric_stagnation_count`を0へ、`features_pass_fail`を空配列へ戻す。
3. `sprint_branch`、`effective_generator_backend`、`last_agent`をnullへ、`negotiation_round`を0へ戻す。
4. Step 1の4層backend解決を再実行し、backendが変わればprogress.mdへ記録する。
5. このturnの最後の永続書き込みとして`pending_worker_exit = true`を保存する。
6. interactive modeではAskUserQuestionで`Proceed to sprint <n+1>?`と確認し、Step 3へ戻る。

次のsprintがなければ、完了した全sprintのPRがnullでないことを確認し、`completed = true`、`phase = "done"`、`pending_worker_exit = true`を保存してStep 10へ進む。

`cumulative_cost_usd`はepic全体で保持する。遷移中に`phase = "ready-for-loop"`を書かない。supervisorは`phase = "negotiation"`を観測し、そのcursorから次のworkerを開始する。

## Step 10：最終報告

完了時にepic名、sprint、PR URL、総cost、経過時間、iteration数、abortしたsprintと理由を報告する。progress.mdへ`decision: epic=<name> completed sprints=<N> cost=<$> iters=<total>`を追記する。

abortまたは`rubric_stagnation`が発生した場合、`/harness-rules-update`を提案する。

## Error Handling

| 状況 | 対応 |
|---|---|
| `.harness/_config.yml`がない | `/harness-init`を先に実行するよう伝える |
| roadmap.mdがない | `/harness-plan`を先に実行するよう伝える |
| `jq`または`git`がない | 停止して導入を求める |
| `tracker=github`で`gh`がない | abortし、trackerを黙って変更しない |
| Generator dispatchが失敗 | phase別feedbackへ記録し1回再試行し、再失敗時は`pending_human=true`とする |
| Evaluator toolが使えない | `verdict: fail, reason: tool-unavailable`を記録し、rubric stagnationに停止させる |
| `git commit`が失敗 | 記録して続行し、hookを回避しない |
| round 3後もPlanner rulingがない | `pending_human=true`として停止する |
| `_state.json`をparseできない | 上書きせず停止し、gitからの復旧を求める |
| non-interactive modeでAskUserQuestionへ到達 | bugとして扱い、`_config.yml`のdefaultを使ってprogress.mdへ警告する |
