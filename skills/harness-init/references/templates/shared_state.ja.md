<!--
  shared_state.md — スプリントレベルの共有台帳。

  書き込み: Orchestrator のみ（harness-loop）
  読み込み: Planner / Generator / Evaluator（全エージェント）

  各エージェントの個別思考・交渉内容は
    sprints/sprint-<N>-<feature>/feedback/{planner,generator,evaluator}-<iter>.md
  に書く。書き込み競合を避け、このファイルを唯一の正式記録とするための設計。
  詳細: .specs/harness-suite/design.md §9.5

  **APPEND-ONLY**。既存エントリの編集禁止。新しい日付エントリを追加する。
-->

# Shared State — Sprint <N> (<feature-name>)

## Plan（計画）
<!--
  Orchestrator が Planner のブリーフをここに要約（contract.md の goal +
  acceptance_scenarios をコピー）。Planner が再計画した時に更新する。
-->

- _未記入_

## Contract（確定契約）
<!--
  交渉完了後の凍結された contract への参照（コミット SHA 付き）
  形式: `sprint-<N>-contract.md @ <SHA>`
-->

- _交渉完了待ち_

## Negotiation（交渉要約）
<!--
  Orchestrator が各 round の結果を要約する。
  エージェント個別の生メッセージは feedback/{role}-<iter>.md 側にある。
  ここは簡潔に round 番号と合意結果のみ記述。
-->

- _Round 1 待ち_

## WorkLog（作業ログ）
<!--
  Generator iteration の要約。タイムスタンプ付き。
  形式: `[<ISO-8601>] iter=<N> agent=generator action=<要約> commit=<SHA>`
  詳細は feedback/generator-<iter>.md 側に書く。
-->

- _iteration なし_

## Evaluation（評価結果）
<!--
  Evaluator の判定要約。タイムスタンプ付き。
  形式: `[<ISO-8601>] iter=<N> agent=evaluator verdict=<pass|fail> axes=<...>`
  Evidence（スクショ・trace）と rubric 生スコアは feedback/evaluator-<iter>.md と
  evidence/ ディレクトリ側に書く。
-->

- _評価なし_

## Decisions（確定事項）
<!--
  Orchestrator が不可逆な状態遷移を記録する:
    - sprint status 遷移（negotiating → active → done | aborted）
    - Principal Skinner 停止（理由、停止時の _state.json カーソル）
    - PR 作成（PR 番号、bundling モード）
    - 人間エスカレーション（pending_human 設定、承認者、resume 時刻）
-->

- _未記入_
