# 機械検査

検査を実行する前に読む。指摘は見直し候補であり、自動的に置換する命令ではない。

```bash
checker="<スキルのディレクトリ>/references/scripts/ja-humanizer-check.mjs"
node "$checker" --mode mail path/to/text.md
node "$checker" --mode article --json path/to/text.md
node "$checker" --mode argument --doc-type spec --word-list /path/to/words.json --json draft.md
node "$checker" --mode article --voice ~/.agents/voice/argument.md draft.md
```

## 入力と結果

`--mode` は `article`、`mail`、`argument`、`narrative`。既存の呼び出し方はそのまま使える。`--doc-type` は `pr`、`spec`、`incident`、`minutes`、`article`、`proposal`、`slides`、`mail`、`manual`。種類はモードを変更せず、形式に関する規則の一部だけを外す。未指定なら従来の規則を使う。除外するIDは[文書別資料](document-types.ja.md)を参照する。

`--word-list` の形式と選び方は[語彙の好み](word-preferences.ja.md)を参照する。公開関数 `analyzeText` は任意のオプション `docType` と `wordList` を受け取る。

終了コードは第1級があれば1、なければ0。`--warn` では第1級があっても0。不正な種類、引数不足、読めない設定や不正なJSONは2として報告する。`--json` は結果をJSONで返し、`--lang en` は質問を英語にする。ファイルの代わりに標準入力も使える。

人が読む形式は `TIER1<tab>id<tab>file:line<tab>message[<tab>question]`。末尾は `JA_HUMANIZER_CHECK_SUMMARY` と PASS/FAIL、等級別件数、読点の比率。`<!-- ja-humanizer-disable-next-line -->` の次の行、コード、インラインコード、表、frontmatter は読まない。

## 検出候補

既存IDと閾値の詳細は[パターン表](patterns.ja.md)と[英語版の検査仕様](checking.md)にある。`calque`、`vocab-density`、装飾と箇条書きの密度、`count-repeat`、`negation-closer`、`section-closer-repeat`、`comparison-without-consequence` などを引き続き使う。

追加した第2級のIDは次のとおり。

| ID | 候補 |
|---|---|
| `vague-breakage` | ソフトウェアの曖昧な「壊れる」 |
| `vague-effect` | 「地味に効く」 |
| `obvious-opener` | 文頭の「もちろん、」 |
| `copy-fragments` | 短い句を重ねるコピー調 |
| `heading-colon` | 「とは：」「とは:」で語句をつなぐ見出し |
| `project-word` | 設定で見直す対象とした文字列 |

狭い型を探す検査であり、意味全体を判断するものではない。今回の用語検査は引用を除外するが、既存規則の除外範囲は変えない。大げさな名詞、本文とつながらない比喩の見出し、根拠のない原因説明は文脈で点検する。検出できない文を確認済みと扱わず、一律の置換規則を増やして対応しない。

## 文体見本と読み直し

`--voice` では平均文長、80字以上の文の割合、接続助詞でつなぐ文の割合を本文と見本で比べる。平均文長が見本の0.75倍未満、または接続文の割合が20ポイント以上少ない場合は `rhythm-mismatch` を出す。本人の手書き抜粋だけを測り、AIの下書きを直した抜粋から文長目標を作らない。初学者向け解説では `--voice` を付けず、スライドの断片にも文長目標を当てない。

検査がPASSでも本文を通読する。語の意味、必要な否定、本人の体験、条件、効果の説明を確認する。検査結果と文脈判断は区別する。通常の生成では記録を内部に置き、確認事項と実行できなかった検査は必要に応じて伝える。このスキルでフックを導入したり、投稿を止めたりしない。
