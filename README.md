# yamisskey-backup

MisskeyのPostgreSQLデータベースを定期的にバックアップし、複数のオブジェクトストレージに安全に保存するDockerベースの自動バックアップツール。

## 特徴

- 🔄 二重バックアップ（Cloudflare R2 + Backblaze B2）
- 📦 7-Zipによる高圧縮
- ⏰ 自動実行（cron、デフォルト: 毎日3:00, 15:00）
- 🔔 Discord通知
- 🗑️ ライフサイクルポリシーによる自動削除

## セットアップ

### 1. 設定ファイルの作成

```bash
cp config/.env.sample config/.env
nano config/.env
```

必須項目を設定：

```bash
# PostgreSQL
POSTGRES_HOST=db
POSTGRES_USER=your_user
POSTGRES_DB=your_db
PGPASSWORD=your_password

# Cloudflare R2
RCLONE_CONFIG_R2_ENDPOINT=https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com
RCLONE_CONFIG_R2_ACCESS_KEY_ID=your_key
RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=your_secret
R2_PREFIX=backups

# Backblaze B2
RCLONE_CONFIG_B2_TYPE=b2
RCLONE_CONFIG_B2_ACCOUNT=your_account_id
RCLONE_CONFIG_B2_KEY=your_application_key
B2_BUCKET=your-bucket
B2_PREFIX=backups

# Discord通知（オプション）
NOTIFICATION=true
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_WEBHOOK
```

### 2. 起動

```bash
docker compose up -d
docker compose logs -f
```

## ライフサイクルポリシー設定

30日経過後に自動削除：

```bash
# Cloudflare R2
export AWS_ACCESS_KEY_ID=your_r2_key
export AWS_SECRET_ACCESS_KEY=your_r2_secret

aws s3api put-bucket-lifecycle-configuration \
  --endpoint-url https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com \
  --bucket your-bucket \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "Auto-delete-old-backups-30days",
      "Status": "Enabled",
      "Filter": {"Prefix": "backups/"},
      "Expiration": {"Days": 30}
    }]
  }'

# Backblaze B2
# B2のライフサイクルルールはWebコンソールまたはb2 CLIで設定
# Bucket Settings > Lifecycle Settings > Keep only the last version
```

## 運用コマンド

```bash
# 手動実行
docker exec misskey-backup /usr/local/bin/misskey-backup

# ログ確認
docker compose logs -f

# 再起動
docker compose restart

# 設定変更後の再ビルド
docker compose down
docker compose build --no-cache
docker compose up -d
```

## トラブルシューティング

```bash
# PostgreSQL接続確認
docker exec misskey-backup psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 1"

# rcloneリモート確認
docker exec misskey-backup rclone listremotes

# R2アクセステスト
docker exec misskey-backup rclone lsd r2:

# B2アクセステスト
docker exec misskey-backup rclone lsd b2:
```

## アーキテクチャ

```
Docker Container (cron)
  ├─ pg_dump → 7z圧縮
  ├─ rclone → Cloudflare R2 (無料10GB)
  └─ rclone → Backblaze B2 (無料10GB)
         ↓
    30日後自動削除
```

## ライセンス

MIT License
