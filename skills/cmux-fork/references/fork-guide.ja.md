# cmux-fork リファレンスガイド

## 概要

cmux-fork は現在の Claude Code の会話を新しい cmux ペインまたはワークスペースにフォークします。`claude --continue --fork-session` により、フォーク先で会話履歴が完全に引き継がれます。

## 使用する cmux コマンド

### `cmux new-split {direction}`

現在のペインを指定方向に分割し、新しいターミナルサーフェスを作成します。

```bash
cmux new-split right   # 右に分割
cmux new-split down    # 下に分割
```

**出力形式:** `OK surface:{N} workspace:{N}`

### `cmux new-workspace`

現在のウィンドウに新しいワークスペース（タブ）を作成します。

```bash
cmux new-workspace
```

**出力形式:** `OK surface:{N} workspace:{N}`

### `cmux send --surface surface:{N} "{command}"`

指定したサーフェスにテキスト入力を送信します。

```bash
cmux send --surface surface:31 "claude --continue --fork-session\n"
```

末尾の `\n` は改行（Enter キー押下相当）を送信します。

### `cmux read-screen --surface surface:{N}`

指定したサーフェスの現在の画面内容を読み取ります。

```bash
cmux read-screen --surface surface:31
```

フォーク先で Claude Code が起動したことの確認に使用します。

### `cmux identify --json`

現在のサーフェス/ペイン/ワークスペースのコンテキストを返します。フォーク前のトポロジー確認に便利です。

```bash
cmux identify --json
```

## 使用例

### 基本的なフォーク（デフォルト: 右）

```
ユーザー: /cmux-fork
エージェント: 右ペインにフォーク
```

```
ユーザー: 「フォークして」
エージェント: 右ペインにフォーク（デフォルト）
```

### 下方向にフォーク

```
ユーザー: 「下にフォークして」
ユーザー: "Fork down"
エージェント: 下ペインにフォーク
```

### 新しいワークスペースにフォーク

```
ユーザー: 「新しいワークスペースでフォークして」
ユーザー: "Fork to a new workspace"
エージェント: 新しいワークスペースを作成してフォーク
```

## エラーケースとトラブルシューティング

### 「cmux セッション内で実行されていません」

**原因:** 環境変数 `CMUX_SOCKET_PATH` が設定されていません。

**対処:** cmux のターミナルセッション内で Claude Code を起動してください。

### フォークコマンドが失敗する

**原因:** `claude --continue --fork-session` は既存のセッション履歴が必要です。

**対処:** 初回起動直後（履歴なし）ではフォークできません。しばらく使ってからフォークしてください。

### フォーク後にプロンプトが検出されない

**原因:** Claude Code のフォークセッション初期化に数秒かかることがあります。

**対処:** 数秒待ってから新しいペインを手動で確認してください。スキルは 3 秒後に自動リトライします。

### 権限が引き継がれない

**想定動作:** セッションスコープの権限はフォーク先に引き継がれません。新しいセッションでツール権限を再承認する必要があります。

## アーキテクチャ

```
Window（ウィンドウ）
└── Workspace（ワークスペース = タブ）
    └── Pane（ペイン = 分割領域）
        └── Surface（サーフェス = ターミナル内容）
```

- **ペイン分割** (`new-split`): 現在のワークスペース内に新しいペインを作成。横並びで作業したいときに最適。
- **新ワークスペース** (`new-workspace`): 新しいタブを作成。独立した作業を切り替えたいときに最適。

## 関連スキル

- **cmux-delegate**: 別の AI エージェント（Codex、Gemini CLI）を特定のタスク付きで起動します。会話のフォークではなく、タスクの委任をしたい場合に使います。
- **cmux-second-opinion**: 別の AI の視点からレビューを受けます。
