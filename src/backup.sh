#!/bin/sh

# バックアップディレクトリの作成（日付別）
BACKUP_DATE=$(TZ='Asia/Tokyo' date +%Y-%m-%d)
BACKUP_DIR="/opt/misskey-backup/backups/${BACKUP_DATE}"
mkdir -p "$BACKUP_DIR"

# バックアップファイル名の生成
BACKUP_FILE="${BACKUP_DIR}/${POSTGRES_DB}_$(TZ='Asia/Tokyo' date +%Y-%m-%d_%H-%M).sql"
COMPRESSED="${BACKUP_FILE}.7z"

# PostgreSQLダンプの作成
pg_dump -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB > "$BACKUP_FILE" 2>> /var/log/cron.log

# 7-Zipで圧縮
7z a "$COMPRESSED" "$BACKUP_FILE"

# Cloudflare R2にアップロード
rclone copy --s3-upload-cutoff=5000M --multi-thread-cutoff 5000M "$COMPRESSED" backup:${R2_PREFIX}

# Filenにアップロード
export PATH=$PATH:/root/.filen-cli/bin
FILEN_STATUS=0
filen --email $FILEN_EMAIL --password $FILEN_PASSWORD upload "$COMPRESSED" "/backups/misskey/${BACKUP_DATE}/" || FILEN_STATUS=$?

# 成功確認 (R2とFilenの両方)
if [ $? -eq 0 ] && [ $FILEN_STATUS -eq 0 ]; then
   echo "Backup succeeded" >> /var/log/cron.log

   if [ -n "$NOTIFICATION" ]; then
       curl -X POST -F content="✅バックアップが完了しました。(${COMPRESSED})" ${DISCORD_WEBHOOK_URL} &> /dev/null
   fi

   # 古いバックアップの削除
   CUTOFF_DATE=$(date -d "7 days ago" +%Y-%m-%d)
   BACKUPS=$(filen --email $FILEN_EMAIL --password $FILEN_PASSWORD ls /backups/misskey/ | grep -v "$CUTOFF_DATE")

   for backup in $BACKUPS; do
       filen --email $FILEN_EMAIL --password $FILEN_PASSWORD rm "/backups/misskey/$backup"
   done
else
   echo "Backup failed" >> /var/log/cron.log

   if [ -n "$NOTIFICATION" ]; then
       curl -X POST -F content="❌バックアップに失敗しました。ログを確認してください。" ${DISCORD_WEBHOOK_URL} &> /dev/null
   fi
fi

# ローカルファイルの削除
rm -rf "$BACKUP_FILE"
rm -rf "$COMPRESSED"
