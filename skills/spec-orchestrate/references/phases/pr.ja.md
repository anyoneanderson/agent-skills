# フェーズ: pr

pull requestを作成または更新し、本文をレビュー判断の索引として組み立てる。
停滞または未検証の実行は、マージ可能と主張せずdraftで着地させる。

## 入力

- 実装差分と最終仕様
- レビュー、受け入れ評価、fallback、裁定の運転記録
- 先送りしたfindingと、作成済みの後続Issue
- `issue-to-pr-workflow.md`のブランチ規約とPR規約
- リポジトリのpull requestテンプレートとPR本文規約

## アクション

1. spec-implementの最終ステップに従ってブランチ、コミット、ベースを準備し、PR作成コマンドは本文完成後まで実行しない。
   ブランチとコミットの規約は`issue-to-pr-workflow.md`に従う。
   実装ファイルと、プロジェクト方針でコミットする場合だけ仕様4ファイルを明示pathspecでステージする。
   運転記録（`evidence/`、`review-*.md`、`inspection-report.md`、`.inspection_result.json`、`evaluate-*.md`、`pipeline-state.json`、`retrospective.md`、`pipeline-metrics.jsonl`）はステージしない。
2. 本文を作る前に、プロジェクトのpull requestテンプレートと本文規約を読む。
   見出し、順序、チェック項目、必須フィールドを維持する。
3. `../pr-assembly.ja.md`に従って本文を作る。
   レビュー判断を変える事実だけを選び、レビューラウンド、全finding、受け入れ合否表、Evidence Manifest、裁定履歴の全文を追加しない。
4. 選別した本文と現在のゲートが要求するdraft状態でPRを作成し、返されたURLを後続Issueのリンクに使う。
5. `fix_before: trial`、`required_check`、`follow_up`で持ち越したfindingの後続Issueを作る。
   finding全文、severity、期限となる段階、対象、発生ラウンド、PRへのリンクはIssueへ保存する。
   PR本文にはIssueへのリンク、変更後の挙動への影響、今回着地できる理由だけを書く。
   同じクラスのfindingは1つのIssueへまとめてもよい。
   作成したIssueへのリンクでPR本文を更新する。
   Issue作成に失敗した場合は、findingがローカル運転記録にしか存在しない状態を避けるため、全文と警告をPR本文へ残す。
6. Minor findingは、レビュー判断を変える場合または目に見える制約を説明する場合だけ残す。
7. 裁定経由でprへ到達した場合、受け入れ評価が不合格またはblockedの場合、先送りfindingの永続的な保存先がない場合はdraftにする。
   マージを妨げる各未解決事項の影響と次の作業を記載する。

## 出力

- 変更後の挙動、判断理由、影響範囲、既知の制約、確認結果、レビュー観点をレビュワーが探せる、プロジェクト規約に従ったpull request
- 作成できた全後続IssueのURL

## 検証

- GitHubクライアントがPR URLを返し、実際のdraft状態と本文が一致する。
- プロジェクトテンプレートの必須見出しと必須フィールドがすべて存在する。
- 本文がレビューラウンド、全finding、受け入れ合否表、Evidence Manifest、裁定履歴の全文を一括転記していない。
- 先送りした全findingに、後続Issueへのリンクまたは全文とIssue作成失敗の警告がある。
- ready PRは受け入れ評価が合格し、マージを妨げる未解決事項がない。

## state更新

- `phase`を`retrospective`にする。
- `pr`を`{"url":"<URL>","draft":<boolean>,"status":"draft|ready"}`として記録し、後続Issue番号を`deferred_issues`へ記録する。
- `status`は意図した作成modeではなく、実際のPR状態から導出する。
- `completed_phases`に`pr`を追加する。

## 遷移

- PR作成または更新、readyまたはdraftの後に**retrospective**へ進む。
