<!-- Issue #162 dogfood edit history, anonymized structural reproduction. -->

Closes #42

## 要約

- バッチ出力を非同期jobとして実行し、完了後に結果を保存する。
- worker、API、共有エラー処理を変更する。

## 実装の詳細

1. APIが要求を検証してqueued jobを作成する。
2. workerが12段階の処理を順に実行する。
3. 共有クライアントが全イベントを転送する。

## Adversarial Review History

- 仕様レビュー: 7 rounds、最終Gate PASS。
- 実装レビュー: 3 rounds、最終Gate PASS。
- push前レビュー: 3 rounds、最終Gate PASS。
- Deferred findings: required_check 4件、trial 3件、follow_up 14件、Minor 17件。
- Arbitration: round 2で担当を変更し、round 3で続行した。

## Acceptance Evidence

| Case | Requirement | Verify | Verdict |
|---|---|---|---|
| T-A01 | REQ-001 | command | PASS |
| T-A02 | REQ-002 | command | PASS |
| T-A03 | REQ-003 | file-check | PASS |
| T-A04 | REQ-004 | command | PASS |
| T-A05 | REQ-005 | command | PASS |

### Evidence Manifest

| File | Bytes | sha256 |
|---|---|---|
| evidence/3/T-A01.log | 1048 | 1111111111111111 |
| evidence/3/T-A02.log | 2048 | 2222222222222222 |

## レビュー指摘の全対応

- round 1の指摘1を修正した。
- round 1の指摘2を修正した。
- round 2の指摘1を修正した。
- round 3の指摘1を修正した。

## 品質ゲート

- unit test 1,919件が合格した。
- coverage statements 85.9%、branches 77.9%だった。
- lint、typecheck、buildが合格した。

## 先送りした指摘

- required_check 4件の全文。
- trial 3件の全文。
- follow_up 14件の全文。
- Minor 17件の全文。
