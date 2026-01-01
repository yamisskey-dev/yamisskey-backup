#!/bin/bash

# 環境変数からrclone設定を生成
cat > /root/.config/rclone/rclone.conf << EOF
[r2]
type = s3
provider = Cloudflare
access_key_id = ${RCLONE_CONFIG_R2_ACCESS_KEY_ID}
secret_access_key = ${RCLONE_CONFIG_R2_SECRET_ACCESS_KEY}
region = auto
endpoint = ${RCLONE_CONFIG_R2_ENDPOINT}
bucket_acl = ${RCLONE_CONFIG_R2_BUCKET_ACL:-private}

[b2]
type = b2
account = ${RCLONE_CONFIG_B2_ACCOUNT}
key = ${RCLONE_CONFIG_B2_KEY}
EOF

# cronジョブを生成（環境変数を直接埋め込み）
cat > /etc/cron.d/misskey-backup << EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
POSTGRES_HOST=${POSTGRES_HOST}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_DB=${POSTGRES_DB}
PGPASSWORD=${PGPASSWORD}
R2_PREFIX=${R2_PREFIX}
B2_BUCKET=${B2_BUCKET}
B2_PREFIX=${B2_PREFIX}
NOTIFICATION=${NOTIFICATION}
DISCORD_WEBHOOK_URL=${DISCORD_WEBHOOK_URL}

# Run at 3:00 and 15:00 every day
0 3,15 * * * root /usr/local/bin/misskey-backup >> /var/log/cron.log 2>&1

EOF

chmod 0644 /etc/cron.d/misskey-backup

# cronを起動してログを監視
cron && tail -f /var/log/cron.log