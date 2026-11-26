# 文書の用途別規則

依頼された文書から種類を選び、該当する資料だけを読む。3モードと本人の文体見本は維持する。種類が分からなければ未指定で進める。種類だけを理由に敬体・常体を変えない。

| 種類 | 資料 | 通常のモード |
|---|---|---|
| `pr` | [PR・Issue本文](doc-types/pr.ja.md) | `argument` |
| `spec` | [仕様書・設計書](doc-types/spec.ja.md) | `argument` |
| `incident` | [障害報告](doc-types/incident.ja.md) | `argument` |
| `minutes` | [議事録](doc-types/minutes.ja.md) | `argument` |
| `article` | [記事・読み物](doc-types/article.ja.md) | `argument / narrative` |
| `proposal` | [提案書](doc-types/proposal.ja.md) | `argument` |
| `slides` | [スライド](doc-types/slides.ja.md) | `argument / narrative` |
| `mail` | [メール・チャット](doc-types/mail.ja.md) | `mail` |
| `manual` | [手順書](doc-types/manual.ja.md) | `argument` |

文書別の例外は文章の形式だけに適用する。事実、条件、推量、本人の文体見本を守る規則は外さない。明示された依頼と本人の文体見本を優先し、種類の規則はその範囲内で使う。語の設定は[語彙の好み](word-preferences.ja.md)を参照する。

初学者向け解説は明示指定が必要で、article を選んだだけでは適用しない。

着想: [yomiyasu v3.4.1 の文書別資料](https://github.com/nanaism/yomiyasu/tree/3979c750b5e1fe9892bd47bb354f0fb51d534ff2/skills/yomiyasu/references/doc-types)（MIT）。ここでの規則と分類は ja-humanizer 向けに独立して記述した。
