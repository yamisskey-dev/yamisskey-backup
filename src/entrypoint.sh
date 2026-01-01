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

# 環境変数を含むcrontabファイルを生成
envsubst < /etc/cron.d/crontab.template > /etc/cron.d/misskey-backup

# crontabファイルのパーミッションを設定
chmod 0644 /etc/cron.d/misskey-backup

# cronを起動してログを監視
cron && tail -f /var/log/cron.log