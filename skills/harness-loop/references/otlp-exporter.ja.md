# OTLP Exporter（任意）

REQ-092 を扱う。`.harness/metrics.jsonl` を読んで OpenTelemetry Protocol
（OTLP）エンドポイントへ iter 毎メトリクスを転送する任意のサイドプロセス。
コスト・rubric 推移・ツール失敗率を他プロジェクト telemetry と並べて見る
ために用いる。

有効化条件は**両方**:

- `_config.yml.hook_level == "strict"`
- `_config.yml.otlp_endpoint` が非空 URL

それ以外では本 reference は情報提供。exporter スクリプト自体は出荷される
が no-op。

## インストール

`harness-init` は `hook_level == strict` の時
`.harness/scripts/metrics-exporter.sh` を配置する。スクリプトは
idempotent ではない: 2 回起動すると cursor ファイルで tail reader が race
する。常にプロジェクトあたり 1 インスタンスのみ動作させる。

典型的なデプロイパターン:

- **session スコープ** — `harness-loop` と並行起動、session 終了で停止。
  interactive / continuous モード向け
- **長期稼働** — macOS なら `launchd`、Linux なら `systemd --user` 配下で
  session を越えて稼働。`autonomous-ralph` と `scheduled` モード向け

## 呼び出し

foreground（デバッグ用）:

```bash
.harness/scripts/metrics-exporter.sh
```

detach（夜間用）:

```bash
nohup .harness/scripts/metrics-exporter.sh >> .harness/otlp.log 2>&1 &
disown
```

停止:

```bash
pkill -f '.harness/scripts/metrics-exporter.sh'
```

## エクスポート対象

`metrics.jsonl` の新規行は以下 instrument を持つ 1 OTLP メトリクスバッチに
変換される:

| Instrument | Type | Unit | ソース field |
|---|---|---|---|
| `harness.iter.duration` | histogram | ms | `duration_ms` |
| `harness.iter.input_tokens` | histogram | {token} | `input_tokens` |
| `harness.iter.output_tokens` | histogram | {token} | `output_tokens` |
| `harness.iter.cost` | histogram | {USD} | `cost_usd` |
| `harness.iter.tool_calls` | histogram | {call} | `tool_calls` |
| `harness.iter.tool_failures` | histogram | {fail} | `tool_failures` |
| `harness.rubric.score` | gauge | 1 | `rubric_scores.<axis>`（軸毎 1 gauge） |
| `harness.iter.cost_cumulative` | counter | {USD} | `cost_usd` の累積和 |

全エミッション共通の resource attributes:

- `service.name = "harness"`
- `harness.epic = <current_epic>`
- `harness.sprint = <sprint>`
- `harness.agent = <agent>`（generator / evaluator / orchestrator）
- `harness.mode = <interactive|continuous|autonomous-ralph|scheduled>`

## cursor ファイル

exporter は `.harness/.metrics-cursor` に byte offset を保持し、再起動時に
前回停止点から再開する。起動時:

```bash
cursor=$(cat .harness/.metrics-cursor 2>/dev/null || echo 0)
tail -F -c +$((cursor+1)) .harness/metrics.jsonl | while read -r line; do
  # OTLP へ emit
  cursor=$(stat -f %z .harness/metrics.jsonl)   # macOS; Linux は -c %s
  printf '%s' "$cursor" > .harness/.metrics-cursor
done
```

cursor ファイル不在時は現 EOF から開始（過去 metrics は既視として扱う）。
`METRICS_REPLAY=1` で offset 0 から再送可能。

## エンドポイントと認証

サポート:

- OTLP/HTTP JSON（`_config.yml.otlp_endpoint`、例:
  `https://collector.internal/v1/metrics`）
- bearer token 認証（`OTLP_AUTH_BEARER` 環境変数）
- mTLS（`OTLP_CLIENT_CERT` + `OTLP_CLIENT_KEY` 環境変数、任意）

gRPC OTLP は v1 非サポート — shell exporter は依存を軽くするため `curl`
利用。collector が gRPC のみなら OTLP/HTTP を localhost で受ける sidecar
translator（OpenTelemetry Collector など）を併用する。

## ヘルスと backpressure

失敗モード:

| 失敗 | 挙動 |
|---|---|
| endpoint 5xx / timeout | 指数バックオフ（1s, 4s, 16s）で 3 回まで再試行。最終失敗は `.harness/otlp.log` にログしその行をスキップ。**metrics.jsonl を溜めない** |
| endpoint 4xx | 再試行なし。payload prefix と行 offset をログしスキップ |
| 起動時 endpoint 到達不可 | 警告ログを出し exit 0。ユーザ設定修正 |
| `metrics.jsonl` rotation（truncate） | cursor を 0 に自動リセット |

exporter は **決して** `harness-loop` をブロックしない。メトリクス export は
ベストエフォート — 1 行 drop でループは止まらない。永続記録は
`metrics.jsonl` 自体、OTLP は live view。

## 動作確認

```bash
# 1. 設定確認
jq -r '.hook_level, .otlp_endpoint' .harness/_config.yml

# 2. 偽 iteration 行を書く
printf '{"ts":"%s","iter":0,"sprint":1,"agent":"test","duration_ms":100,"cost_usd":0.01,"rubric_scores":{"functionality":0.5},"tool_calls":1,"tool_failures":0}\n' \
  "$(date -u +%FT%TZ)" >> .harness/metrics.jsonl

# 3. collector で確認
curl -s "$OTLP_DEBUG_URL" | jq '.resourceMetrics[-1]'
```

## 無効化

再 init なしで無効化:

```bash
yq -y '.otlp_endpoint = ""' .harness/_config.yml > /tmp/_config.yml
mv /tmp/_config.yml .harness/_config.yml
pkill -f '.harness/scripts/metrics-exporter.sh'
```

exporter の no-op 経路は tick 毎に `otlp_endpoint` を確認し、クリアされて
いれば正常終了する。

## 本 reference の非対象

- ログ転送（`progress.md` → logging pipeline）— v1 スコープ外
- トレースエクスポート（tool 毎 span）— Anthropic SDK は OTLP span を
  native 出力しない。native サポート追加時に再検討
- ダッシュボード — 任意の OTLP 互換バックエンド（Grafana Mimir, Honeycomb,
  Datadog 等）を選択
- 保持ポリシー — collector / バックエンドに委譲
