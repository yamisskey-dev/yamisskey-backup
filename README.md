# yamisskey-backup

MisskeyのPostgreSQLデータベースを定期的にバックアップし、複数のオブジェクトストレージに安全に保存するDockerベースの自動バックアップツール。

## 特徴

- 🔄 二重バックアップ（Cloudflare R2 + Linode Object Storage）
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

# Linode Object Storage
RCLONE_CONFIG_LINODE_ENDPOINT=https://jp-osa-1.linodeobjects.com
RCLONE_CONFIG_LINODE_ACCESS_KEY_ID=your_key
RCLONE_CONFIG_LINODE_SECRET_ACCESS_KEY=your_secret
LINODE_BUCKET=your-bucket
LINODE_PREFIX=backups

# Discord通知（オプション）
NOTIFICATION=true
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_WEBHOOK
```

### 2. rclone.confの作成

```bash
nano config/rclone.conf
```

```ini
[r2]
type = s3
provider = Cloudflare
access_key_id = your_key
secret_access_key = your_secret
region = auto
endpoint = https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com
bucket_acl = private

[linode]
type = s3
provider = Other
access_key_id = your_key
secret_access_key = your_secret
endpoint = https://jp-osa-1.linodeobjects.com
acl = private
```

### 3. 起動

```bash
docker compose up -d
docker compose logs -f
```

## ライフサイクルポリシー設定

30日経過後に自動削除：

```bash
# Linode
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret

aws s3api put-bucket-lifecycle-configuration \
  --endpoint-url https://jp-osa-1.linodeobjects.com \
  --bucket your-bucket \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "Auto-delete-old-backups-30days",
      "Status": "Enabled",
      "Filter": {"Prefix": "backups/"},
      "Expiration": {"Days": 30}
    }]
  }'

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

# Linodeアクセステスト
docker exec misskey-backup rclone lsd linode:your-bucket
```

## アーキテクチャ

```
Docker Container (cron)
  ├─ pg_dump → 7z圧縮
  ├─ rclone → Cloudflare R2 (無料10GB)
  └─ rclone → Linode Object Storage ($5/月)
         ↓
    30日後自動削除
```

## ライセンス

MIT License
