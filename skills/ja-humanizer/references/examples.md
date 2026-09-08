# Evaluation Samples

Before/after pairs for checking ja-humanizer's detection and rewriting against real data. "Before" is an AI draft; "after" is the writer's manual fix. Each pair carries a classification into "the skill can fix automatically", "the skill asks", and "the writer decides", plus the detections a check run is expected to report. Names of people, companies and products are masked. The Japanese text is kept as is, because it is the data under test.

## How to Use

- Rewrite check: feed the before text and see whether the output contains the same kind of change as the after text (same place, same direction). Identical wording is not required.
- Detection check: run the before text through the check script and see whether the items under "expected detections" appear in the findings.
- Over-editing check: feed the after text and confirm that no rewrite happens. The after text is the writer's own prose, so any change here means a rule is too strong.

## Rewrites 1 to 3 (explanatory article, argument mode)

Source: three passages of a public article judged to be AI-generated, rewritten by the writer.

### Rewrite 1 (heading)

before: 同じ週に、Google と Anthropic も同じ方向へ動いた

after: Google と Anthropic も同様の方針へ

Classification:

- Automatic: heading written as a sentence (Tier 2). Staging in 「同じ週に」 (Tier 1). Metaphorical verb 「動いた」 (Tier 1).

### Rewrite 2 (a contrast that stays)

before: モデル全体を閉じるのではなく高度なサイバー能力の部分だけを審査付きで配る設計です。

after: モデルの利用全体を停止するのではなく、サイバー能力のあるモデルのみを限定公開として審査制で利用を許可する。

Classification:

- Automatic: metaphorical verbs 「閉じる」「配る」 (Tier 1). Nominal ending 「設計です」.
- Ask: to whom the model is released. The writer filled this from their own knowledge; the skill must not add it.
- Keep: the 「〜ではなく」 contrast. It corrects an alternative the reader would actually assume (shutting down the whole model), so it stays.

### Rewrite 3 (threatening closer)

before: 最重要システムで、脆弱性の公表から適用完了までに実際に何日かかっているかを、感覚ではなく直近の実績値で測ります。この数字がないと、猶予が縮んだときの危険度を判断できません。

after: 利用しているシステムで脆弱性の発表から実際のパッチ適用まで何日かかっているかの実績を可視化してください。この実績値が AI セキュリティ時代では縮むことを前提に考える必要があります。

Classification:

- Automatic: staging in 「最重要」「感覚ではなく」 (Tier 1). Turn the threatening closer into a premise (Tier 1). Turn the author's action 「測ります」 into an instruction to the reader 「してください」.
- Keep: replacing 「猶予」 with 「実績値が縮む」 is the writer's judgment.

Expected detections: staging words, metaphorical verbs, heading as sentence, threatening closer.

## Tap to Pay (benefits section of an explanatory article)

Source: the benefits section of an article drafted by AI and partly edited by the writer. The writer rewrote one section.

### before

```text
Tap to Payのメリット
導入コストの削減:
従来必要とされていた専用の決済端末を購入するコストが不要となり、スマートフォン一台で導入が可能です。

迅速なセットアップ:
複雑なハードウェアの導入が不要なため、短期間でシステムを立ち上げることができます。

柔軟な運用:
移動販売やイベント、個人商店など、従来のPOSシステムが設置困難な場所でも容易に決済システムを利用できる点も魅力です。

環境に優しい:
紙のレシート発行が減少し、デジタルな取引記録により環境負荷が低減できます。
```

### after

```text
Tap to Payのメリット
コスト削減:
これが最大のメリットとなりますが、スマートフォン一台で導入が可能になるため、従来必要とされていた専用の決済端末を購入する導入コストが不要となります。

早期導入:
従来の複雑なハードウェアの導入が不要になります。電源やWIFI、専用ソフトのインストールなどは不要でスマホにアプリをインストールするだけで短期間でサービスを立ち上げることができます。

POSが置けないような場所でも販売ができる:
移動販売やイベント、個人商店など、従来のPOSレジが設置困難な場所では現金決済が当たりまえでしたが、スマホ一台あれば簡単にキャッシュレス決済が導入できます。

環境への配慮:
副次的な効果ではありますが、通常Tap to Payではスマートフォン1台でやり取りするため、プリンタは接続しない運用が推奨されています。
紙ではなく、電子レシート（メール、SMS等）で送信されますので、紙のレシート発行が減少することにより環境負荷が低減できます。
```

### Classification

- Unchanged: the label-plus-colon structure and the four items. The writer accepts this form, so in explanatory articles it is treated as Tier 3.
- Ask (needs the writer's knowledge): what becomes unnecessary (power, WIFI, dedicated software). The premise that cash used to be the norm. The fact that running without a printer is the recommended setup, and the means of electronic receipts.
- Writer's judgment: the weighting in 「これが最大のメリット」「副次的な効果ではありますが」. The concrete label 「POS が置けない場所でも販売できる」 replacing 「柔軟な運用」.
- Automatic: fix the causal order from "the terminal is unnecessary, so it can be introduced" to "one phone is enough, so buying a terminal is unnecessary". Delete the evaluative 「〜点も魅力です」.

Expected detections: a "thin sentence" question on all four items. The evaluative 「〜点も魅力です」.

## Mail Review 1 (investigation report and choice of response)

Recipient: a client.

### before

```text
原因調査結果について報告いたします。

PH7にて新たに作成したロジック自体には、大きな問題は確認されておりません。一方で、既存ロジックを再利用している箇所があり、その部分については処理負荷の観点でパフォーマンス改善の余地がある可能性がございます。
該当箇所のチューニングは実施可能です。ただし、貴社にて改めて動作確認をお願いする必要がある認識です。

したがって、対応方針としては以下の選択肢が考えられます。

・該当ロジックのチューニングを実施し、動作確認を行う
・一時的にロールバックを行い、負荷状況を安定させる

貴社の運用状況や優先度を踏まえ、どちらの方針で進めるかご検討いただけますと幸いです。
```

### after

```text
原因調査結果について報告いたします。

PH7含めて、既存コードの見直しを行いました。
結果的にはやはり、PH7にて新たに作成したロジック自体には、大きな問題は確認されておりません。一方で、PH7以前より使っている既存ロジックを再利用して呼び出している箇所があり、その部分については処理負荷の観点でパフォーマンス改善の余地がある箇所があり、修正を行うことでパフォーマンスが改善する可能性がございます。
該当箇所のチューニングは実施可能です。ただし、既存コードの修正が入りますので、ステージング上での動作確認をする必要がある認識です。（外部接続部分ではないのですが、貴社での受入れ試験も実施するのが望ましいと考えております。）

したがって、対応方針としては以下の選択肢が考えられます。

対応案1.
前述のパフォーマンスに影響があると思われる既存該当ロジックのチューニングを実施し、動作確認を行う

対応案2.
一時的にPH6のコードへとロールバックを行い、負荷状況を安定させる（PH7のコードのデプロイが、サイトへアクセスできないユーザーが増えた原因だったのかの切り分けも実施可能）

対応案1の実装対応自体は〇〇日でできる見込みです。
貴社の運用状況や優先度を踏まえ、どちらの方針で進めるかご検討いただけますと幸いです。
```

### Classification

- Unchanged: politeness level, paragraph structure, the closing sentence. Not shortened.
- Ask: the work performed (what was done). Which logic (which one). Where and by whom the check happens (who does it where). The rollback target version and its side benefit. The estimate (when it ends).
- Automatic: rewrite 「余地がある可能性」 into the action-and-result form 「修正を行うことで改善する可能性」. Detect that 「ただし〜必要がある」 carries no reason. Number the options so later sentences can refer to them.

Expected detections: missing estimate (when it ends). 「ただし」 without a reason.

## Mail Review 2 (defect report with cause and prevention)

Recipient: a client.

### before

```text
・不具合発生の経緯
管理画面の「利用可能媒体設定」に「タグ」を設定後、会員画面でプリペイドカードの登録を行った際、カードタイプのものが登録できてしまう事象が発覚しました。

・原因・要因
管理画面での「利用可能媒体設定」が会員画面のプリペイドカード登録時に適用されていないことが原因でした。

・再発防止策
要件を満足しない実装内容であったことが本件の根本的な原因であると考えております。
そのため、要件定義書のこまめな更新、社内での要件共有を徹底することで再発を防止できると考えております
```

### after

```text
・不具合発生の経緯
管理画面の「利用可能媒体設定」に「タグ」を設定後、会員画面でプリペイドカードの登録を行った際、カードタイプのものが登録できてしまう事象が発覚しました。

・原因・要因
当初要件定義フェーズ時に「タグ」「プリペイドカード」という分類制御はない要件であり、その後追加でいただいたご要望で「タグ」「プリペイドカード」という要望をいただきました。管理画面の開発を行なったエンジニアは本仕様を考慮して開発を行なっておりましたが、フロント画面の開発を行なったエンジニアが本要件を考慮せず開発を行なってしまったことが原因となります。

・再発防止策
追加の要件を社内で十分に共有できていなかったことが原因と考えております。
要件変更に対する要件定義書の迅速な更新及び仕様変更が発生した場合の社内エンジニアメンバーへの周知を徹底することで再発防止を徹底して参りたいと思います
```

### Classification

- Unchanged: the events paragraph. The three-heading structure and the middle dots.
- Ask: when the requirement came in, who reflected it, who missed it. Which step of the cause each countermeasure closes.
- Automatic detection: the cause section restates the events section. Circular reasoning (「要件を満たさない実装が根本原因」). Countermeasures made of generic words only (こまめ, 徹底, 共有).

Expected detections: a cause that only restates the symptom. Countermeasures of generic words.

## Mail Review 3 (investigation request for a payment error)

Recipient: a client.

### before

```text
調査にあたり、以下の情報をご提供いただけますでしょうか。
・管理画面での決済エラー画面

9月2日10:24頃にマーチャントパスワードが原因とされる「K03」エラーログが確認されましたが、この時間帯に実施された認識で間違いないでしょうか。
上記時間帯に実施いただいているようでしたらマーチャントパスワードが起因しているため、決済代行会社様にも合わせて調査依頼をお願いできますでしょうか。
```

### after

```text
調査にあたり、以下の情報をご提供いただけますでしょうか。
・管理画面での決済エラー画面

9月2日10:24頃にマーチャントパスワードが原因とされる「K03」エラーログが確認されましたが、この時間帯に実施された認識で間違いないでしょうか。「K03」エラーはマーチャントパスワードに起因するエラーですので、やはりマーチャントパスワードが正しく設定されていないことが想定されます。
もし、64桁になる前の旧パスワードをお持ちでまだ有効期限が切れていないようであれば、まずはそちらを設定していただいて問題なく動くかの切り分けなどもしてみていただけますでしょうか？

また、決済代行会社様にも合わせて調査依頼を出していただければ幸いです。
```

### Classification

- Unchanged: the opening request for information and the confirmation of the time window.
- Ask: what the error code means and the suspected state of the cause. A triage step the recipient can run.
- Automatic: remove the conditional request (「実施いただいているようでしたら〜お願いできますでしょうか」) and make it an independent, unconditional request.

Expected detections: a request chained on the other party's reply.

## Over-Editing Check

The following passages are the writer's own and comply with the norms. Feed them and confirm no rewrite appears. Any change means a rule is too strong.

```text
まだかなり緩い案件なのですが、全国2万拠点にそれぞれビーコンを置いて来訪したお客様に対して来店ポイントを差し上げるシステムの提案依頼が当社に来ております。

来店した方の行動分析をとるわけではないので、オーバースペックかなとも思ったのですが、2万拠点一斉導入となれば、ざっくりとした金額感のご提示ができたら良いかと思いまして今回連絡させていただきました。
```

```text
かしこまりました。資金繰りとしては問題ないと思います。グループ内とはいえ、実施した作業に対する対価ですし、請求書を受領いただいておりますのでお支払いをお願いします。
```
