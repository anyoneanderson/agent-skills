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
管理画面の「△△設定」に「□□」を設定後、会員画面でプリペイドカードの登録を行った際、カードタイプのものが登録できてしまう事象が発覚しました。

・原因・要因
管理画面での「△△設定」が会員画面のプリペイドカード登録時に適用されていないことが原因でした。

・再発防止策
要件を満足しない実装内容であったことが本件の根本的な原因であると考えております。
そのため、要件定義書のこまめな更新、社内での要件共有を徹底することで再発を防止できると考えております
```

### after

```text
・不具合発生の経緯
管理画面の「△△設定」に「□□」を設定後、会員画面でプリペイドカードの登録を行った際、カードタイプのものが登録できてしまう事象が発覚しました。

・原因・要因
当初要件定義フェーズ時に「□□」「プリペイドカード」という分類制御はない要件であり、その後追加でいただいたご要望で「□□」「プリペイドカード」という要望をいただきました。管理画面の開発を行なったエンジニアは本仕様を考慮して開発を行なっておりましたが、フロント画面の開発を行なったエンジニアが本要件を考慮せず開発を行なってしまったことが原因となります。

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

9月2日10:24頃に加盟店パスワードが原因とされる「XX03」エラーログが確認されましたが、この時間帯に実施された認識で間違いないでしょうか。
上記時間帯に実施いただいているようでしたら加盟店パスワードが起因しているため、決済代行会社様にも合わせて調査依頼をお願いできますでしょうか。
```

### after

```text
調査にあたり、以下の情報をご提供いただけますでしょうか。
・管理画面での決済エラー画面

9月2日10:24頃に加盟店パスワードが原因とされる「XX03」エラーログが確認されましたが、この時間帯に実施された認識で間違いないでしょうか。「XX03」エラーは加盟店パスワードに起因するエラーですので、やはり加盟店パスワードが正しく設定されていないことが想定されます。
もし、64桁になる前の旧パスワードをお持ちでまだ有効期限が切れていないようであれば、まずはそちらを設定していただいて問題なく動くかの切り分けなどもしてみていただけますでしょうか？

また、決済代行会社様にも合わせて調査依頼を出していただければ幸いです。
```

### Classification

- Unchanged: the opening request for information and the confirmation of the time window.
- Ask: what the error code means and the suspected state of the cause. A triage step the recipient can run.
- Automatic: remove the conditional request (「実施いただいているようでしたら〜お願いできますでしょうか」) and make it an independent, unconditional request.

Expected detections: a request chained on the other party's reply.

## Indexing a PR Body (an AI first draft, corrected under the writer's direction)

Source: a PR body from a work repository. The first draft was about 8,300 characters with 86 bold spans; the final version about 3,200 characters with none. It was corrected to fit the repository's PR template (under 4,000 characters, at most 10 bold spans, no audit records or implementation log). Excerpts from both are shown. Issue numbers and the repository name are masked.

### before (excerpt)

```text
## 要約

- **何を**: GitHub 上の活動からメンバー1人分の働き方レポートを LLM に書かせ、章単位で保存する機能を追加した。専用の生成プログラムは作らず、レポート作成の手順と規範を builtin の多ファイル skill に置き、既存の agent loop を Run として起動して読ませる。
- **なぜ**: 親 Issue のフェーズ2。日別アクティビティ表（フェーズ1）に続いて、実データから働き方の実像を文章で描く部分を作る。
- **影響範囲**: orchestrator と DB が中心。画面は別 Issue の担当。ローカルの dogfooding で見つけた欠陥のため共通ライブラリにも修正が入っている（下記「スコープを広げた3点」）。

## 何が壊れないようにしたか（不変条件）

- **書き込み系ツールが配線されない。** 宣言・テスト・実行時検査の3段で守る。ツール名集合が固定5件と完全一致することをテストで検査し、Run 解決の最後に実行時にも同じ一致を検査して、不一致なら止める。
- **検証に落ちた生成物は保存されない。** 保存の可否は提出バッファと保存前検証だけが決める。

## スコープを広げた3点（いずれも dogfooding が実測で見つけた）

当初の宣言スコープは orchestrator と DB だった。次の3点はローカルで実メンバー1名・実モデルを通して初めて現れたもので、**決定的テスト1919件と受け入れ評価60ケースでは1件も出なかった**。

## レビューと検証

**仕様**: 機械検査（spec-inspect）7ラウンド、Codex による敵対的仕様レビュー3ラウンド（`fix_before: implementation` は 4 → 4 → 0）。

**コード**: push 前の Codex コードレビュー3ラウンド。指摘は段階的に精度が上がり、**いずれも受け入れ評価と決定的テストを通り抜けていた**。

**品質ゲート**: `pnpm gate` exit 0（format / lint / typecheck / build / test）。orchestrator 1919件、agent-runtime 234件、llm-client 80件、contracts 326件、実 DB 統合40件すべて通過。orchestrator のカバレッジは statements 85.9% / branches 77.96% / functions 88.57% / lines 87.52%。

## 先送りした指摘

**`required_check`（後続作業の前に解消したい）4件**、**`trial`（試用の前に解消したい）3件**、**`follow_up` 14件**、**Minor 17件**。詳細は各フェーズのレビューファイルにある（運転記録のためコミットしていない）。
```

### after (excerpt)

```text
Refs #NNN

- GitHub 上の活動から、指定したメンバー1名分のエンジニアレポートを6章構成で生成し、検証後に保存します。
- モデル呼び出しとツール実行を繰り返す既存の agent loop へ読み取り専用ツールと builtin skill を渡し、生成要求は非同期 Run として実行します。
- 本 PR は orchestrator、agent-runtime、DB が対象です。レポート表示画面は別 Issue で実装します。

## 修正理由

レポート専用の実行基盤は作らず、既存の agent loop を再利用しました。
これにより、ツール実行、監査、実行時間制限、エラー処理を既存の Run と共有できます。

当初は同期 API として設計していましたが、実モデルによる初回検証で生成に約337秒かかり、Cloud Run の既定上限300秒を超えました。
そのため、API は202を返し、worker が非同期で生成する方式へ変更しました。

## 動作確認

- [x] ローカルで実メンバー1名を対象に実モデルで生成し、固定6章が保存されることを確認しました。
- [x] 保存した6章の引用が、すべて対象メンバー、対象期間、PR 一覧の範囲内であることを確認しました。

## セルフレビュー（spec-review 指摘と対応）

- 指摘: skill を読まずに章を提出しても保存できる → 対応: skill 本体と参照4件の読み込みを、章提出時と保存前の両方で検査しました。
- 指摘: 別 skill の同名 path を読むことで検査を通過できる → 対応: 読み込み記録を skill 名と path の組で保持するようにしました。

## 未確認事項

- デプロイ済み Service には GitHub PAT が配線されていないため、現時点の staging では生成ルートが登録されず404になります。本 PR は、未登録理由を起動ログへ残すところまでを対象とします。

## レビュワーに確認してほしいこと

- 固定5ツール以外をモデルが利用できる経路がないか
- skill の読み込みと保存前検証を迂回して章を保存できないか
```

### Classification

- Cut: review round counts, test counts, coverage values, detailed timings, the dogfooding defect table, the list of deferred findings, all 86 bold spans, the opening label-plus-colon items, the declarative punchlines.
- Kept: the three opening lines (what, how, scope), reading order, focus points, unverified items, a self-review limited to findings that changed the implementation, follow-up Issues.
- Automatic: implementation-log detection (Tier 1), label-plus-colon (Tier 2 in argument mode), heavy bold.
- Writer's judgment: which findings changed the implementation, what to leave under unverified items.

Expected detections: "implementation-log residue" and label-plus-colon in the before text; no Tier 1 finding in the after text.

## Unverified Facts in a First Draft (from the A/B comparison)

The same prompt was given twice: once with the old norm alone, once with ja-humanizer. The ja-humanizer version had no wording or structure problems (the checker reported zero at every tier) and stated, unprompted and with confidence, facts that were not in the request. The writer confirmed the following two sentences to be wrong or unverified.

```text
日本とアメリカのクレジットカードは主にこの方式（Online PIN）で、日本のデビットカードも同じである。
```

Correct: the US mainly uses Online PIN, Japan mainly uses Offline PIN. The expected behavior is to keep the sentence in the body and list it under the closing 「要確認」 heading.

```text
一定額（日本では1万円前後、加盟店契約で異なる）を超えると Online PIN か、スマートフォン側の生体認証で確認する。
```

The number is not in the request, and the writer confirmed it is wrong: because Japan mainly uses Offline PIN, a contactless payment of 15,000 yen or more either fails or falls back to signature (deprecated). There is a movement toward Online PIN. Same treatment.

Expected output: a closing 「要確認」 heading with one line for each of the two statements above.

## Confirmed Narrative Excerpts

The writer confirmed the following three excerpts as voice examples. That confirmation applies only to the quoted spans. The second excerpt ends mid-sentence; do not use its trailing clause as a sentence-ending template.

```text
気になりだすと、どんどん気になるもので、私も、AI の下書きをずっと手で直し続けたり色んなスキルを入れてAI臭さをなくす取り組みをやり続けています。

まあコンテンツまで全部AI任せでは自分の記事では無くなってしまうので、そこはどこまでやらせるのか賛否両論ありますが、

AIが知り得ない事実や補強すべきコンテンツを与えるのは書き手のオリジナリティが出る部分だと思うので、そこは大事にしました。
```

These excerpts show this writer's ongoing editing experience, an aside about what to delegate, and a personal reason for a design choice. Preserve those meanings and the original wording when they are supplied as approved voice evidence. Do not require first-person openings, asides, hedging or noun-phrase headings in every new article. They do not establish rules about Japanese in general or habits unique to one model.

For an over-editing trial, ask the agent to review these excerpts unchanged. Do not also put them into that trial's voice reference: copying a supplied answer is not evidence of transfer. The fixture `scripts/tests/fixtures/narrative-confirmed.md` checks only that the detector reports no Tier 1 finding. Naturalness still requires reading the output.

The rejected article passages belong to the separate contextual task in [Editorial Evaluation](editorial-evaluation.md#article-revision-case). They are not approved after-text or voice samples.

## Over-Editing Check

The following passages are the writer's own and comply with the norms. Feed them and confirm no rewrite appears. Any change means a rule is too strong.

```text
まだかなり緩い案件なのですが、全国2万拠点にそれぞれビーコンを置いて来訪したお客様に対して来店ポイントを差し上げるシステムの提案依頼が当社に来ております。

来店した方の行動分析をとるわけではないので、オーバースペックかなとも思ったのですが、2万拠点一斉導入となれば、ざっくりとした金額感のご提示ができたら良いかと思いまして今回連絡させていただきました。
```

```text
かしこまりました。資金繰りとしては問題ないと思います。グループ内とはいえ、実施した作業に対する対価ですし、請求書を受領いただいておりますのでお支払いをお願いします。
```
