# 拡張品質検査

`SKILL.md`のプロジェクト規則検査に続けて、Check 14からCheck 19を順番に実行する。

## Check 14：APIとUIの命名一貫性 [WARNING]

WebまたはAPI仕様では、design.mdからendpointを、tasks.mdから画面名またはrouteを抽出する。多数派の規則を特定し、単数形と複数形、動詞を含むREST path、pathの大文字小文字、parameter記法、`Screen`と`Page`のsuffixが少数派だけ異なる場合に報告する。

`WARNING-{seq}`へ`API naming inconsistency: {details}`と具体的な統一案を出力する。

## Check 15：ドキュメント更新分析 [INFO]

README.md、CLAUDE.md、AGENTS.md、検出したcoding-rules.mdまたは`docs/coding-rules.md`、検出したissue-to-pr-workflow.mdまたは`docs/issue-to-pr-workflow.md`、CLAUDE.mdから抽出した文書directoryを確認する。次の対応で仕様と比較する。

- 新機能 → READMEの機能一覧
- 新endpoint → API文書
- 技術変更 → setup guide
- 新規約 → CLAUDE.mdまたはAGENTS.md
- 共有libraryまたはutility変更 → coding-rules.md
- workflow変更 → issue-to-pr-workflow.md
- 新quality gateまたは標準 → coding-rules.md

`INFO-{seq}`へ`Documentation update needed: {filename} — {reason}`を出力する。`### Documentation Update Tasks (auto-detected)`の下へ`- [ ] DOC-001: Update {section} in {filename} ({reason})`形式のtaskを追加するよう提案する。

## Check 16：受入テストのcoverage [WARNING]

test.mdは`## T-A{nn}: [REQ-XXX] ...`形式の見出しと、`playwright`、`command`、`file-check`のいずれかを値に持つ`Verify:`または`検証方法:`を使う。

1. test.mdがなければINFOを1件出力し、残りのcoverage検査を飛ばす。従来の3文書仕様は有効なままとする。
2. 各test IDと、見出しが参照する`REQ`または`NFR` IDを抽出する。
3. 参照するtest caseがない要求を報告する。
4. 検証方法が欠落、空欄、未対応値のtest caseを報告する。

次の出力を使う。

- test.md欠落：`INFO-{seq}`のtitleを`Acceptance test plan (test.md) not found`とし、coverageを検査していないこととfull workflowで生成できることを説明する。
- coverage欠落：`WARNING-{seq}`のtitleを`Acceptance coverage: {covered}/{total} requirements have a test case`とし、未coverageのIDと、IDごとに`T-A` caseを追加する指示を示す。
- 検証方法欠落：`WARNING-{seq}`のtitleを`Test case {case_id} has no verification method`とし、対応する3値のいずれかを指定するよう求める。

## Check 17：参照pathの実在とmode [CRITICAL]

実装が読む必要のあるpathが未追跡の場合や、git tree accessが追跡できないsymlinkの場合、その仕様は実装できない。

1. stepが読み、parseし、またはdiffするrepository相対のcontent source pathを抽出する。例と出力先は除外する。
2. 各pathに`git ls-files -s -- <path>`を実行する。出力なしは未追跡、mode `120000`はsymlinkを表す。`git show HEAD:<path>`はtarget fileの内容ではなくsymlinkのtarget文字列を返す。
3. git objectまたはtree経由で読む場合と、読み方が未指定の場合だけsymlinkを報告する。通常のworking tree readはsymlinkをたどってよい。

出力を分ける。

- 未追跡：`CRITICAL-{seq}`のtitleを`Referenced path {path} is not tracked by git`とし、fileを追跡するか実際の追跡済みpathを指定するよう指示する。
- symlink：`CRITICAL-{seq}`のtitleを`Referenced path {path} is a symlink (mode 120000) used as a content source`とし、symlinkのtargetを指定するよう指示する。

## Check 18：抽象的な処理説明 [WARNING]

primary vocabularyの候補に具体的な振る舞いを決める証拠がない場合だけ報告する。選択した`spec-writing` vocabularyとともに`abstract-process-check` referenceを実行する。Pattern一覧は`spec-writing`だけに置く。file、line、不足する処理要素、具体的な書き換え、対応する`AV-*` ruleを`WARNING-{seq}`へ出力する。

## Check 19：投影一貫性 [WARNING]

選択した`projection-consistency-check` referenceを実行し、そのfinding contractを使う。
