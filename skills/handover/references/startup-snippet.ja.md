<!-- handover:start -->
## Session Handover

セッション開始時にローカルの handover ファイル（`handover.md` または `.handover/current.md`）が存在する場合、変更作業の前に読み込む。

handover を信頼する前に、現在の repository 状態と照合する:

- 現在の branch
- 現在の HEAD
- working tree status
- 参照されている重要ファイル

引き継いだ文脈、古い可能性のある情報、矛盾している情報を要約し、`Next Action` が安全かつ明確な場合のみ続行する。破壊的操作、外部公開操作、曖昧な操作は事前に確認する。
<!-- handover:end -->
