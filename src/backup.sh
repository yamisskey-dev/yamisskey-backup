#!/bin/bash
# 環境変数の読み込み
if [ -f /config/.env ]; then
    source /config/.env
fi

# バックアップディレクトリの作成（日付別）
BACKUP_DATE=$(TZ='Asia/Tokyo' date +%Y-%m-%d)
BACKUP_DIR="/opt/misskey-backup/backups/${BACKUP_DATE}"
mkdir -p "$BACKUP_DIR"

# バックアップファイル名の生成
BACKUP_FILE="${BACKUP_DIR}/${POSTGRES_DB}_$(TZ='Asia/Tokyo' date +%Y-%m-%d_%H-%M).sql"
COMPRESSED="${BACKUP_FILE}.7z"

# PostgreSQLダンプの作成
echo "Creating PostgreSQL dump..." >> /var/log/cron.log
if ! pg_dump -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB > "$BACKUP_FILE" 2>> /var/log/cron.log; then
    echo "Failed to create PostgreSQL dump" >> /var/log/cron.log
    if [ -n "$NOTIFICATION" ]; then
        curl -X POST -F content="❌データベースダンプの作成に失敗しました。" ${DISCORD_WEBHOOK_URL} &> /dev/null
    fi
    exit 1
fi

# 7-Zipで圧縮
echo "Compressing backup file..." >> /var/log/cron.log
if ! 7z a "$COMPRESSED" "$BACKUP_FILE"; then
    echo "Failed to compress backup file" >> /var/log/cron.log
    if [ -n "$NOTIFICATION" ]; then
        curl -X POST -F content="❌バックアップファイルの圧縮に失敗しました。" ${DISCORD_WEBHOOK_URL} &> /dev/null
    fi
    rm -f "$BACKUP_FILE"
    exit 1
fi

# 元のSQLファイルを削除
rm -f "$BACKUP_FILE"

# Cloudflare R2へのアップロード関数
upload_to_r2() {
    echo "Uploading to Cloudflare R2..." >> /var/log/cron.log
    if rclone copy --s3-upload-cutoff=5000M --multi-thread-cutoff 5000M "$COMPRESSED" backup:${R2_PREFIX}; then
        echo "R2 upload succeeded" >> /var/log/cron.log
        return 0
    else
        echo "R2 upload failed" >> /var/log/cron.log
        return 1
    fi
}

# Filenへのアップロード関数
upload_to_filen() {
    echo "Uploading to Filen..." >> /var/log/cron.log
    export PATH=$PATH:/root/.filen-cli/bin
    if filen --email $FILEN_EMAIL --password $FILEN_PASSWORD upload "$COMPRESSED" "/backups/misskey/${BACKUP_DATE}/"; then
        echo "Filen upload succeeded" >> /var/log/cron.log
        return 0
    else
        echo "Filen upload failed" >> /var/log/cron.log
        return 1
    fi
}

# 両方のアップロードを実行
R2_SUCCESS=false
FILEN_SUCCESS=false

# R2へのアップロード
upload_to_r2
if [ $? -eq 0 ]; then
    R2_SUCCESS=true
fi

# Filenへのアップロード
upload_to_filen
if [ $? -eq 0 ]; then
    FILEN_SUCCESS=true
fi

# 結果の通知
if [ "$R2_SUCCESS" = true ] || [ "$FILEN_SUCCESS" = true ]; then
    echo "Backup partially or fully succeeded" >> /var/log/cron.log
    
    if [ -n "$NOTIFICATION" ]; then
        MESSAGE="✅バックアップが完了しました。(${COMPRESSED})\n"
        if [ "$R2_SUCCESS" = false ]; then
            MESSAGE+="⚠️ R2へのアップロードは失敗しました。\n"
        fi
        if [ "$FILEN_SUCCESS" = false ]; then
            MESSAGE+="⚠️ Filenへのアップロードは失敗しました。\n"
        fi
        curl -X POST -F content="$MESSAGE" ${DISCORD_WEBHOOK_URL} &> /dev/null
    fi
else
    echo "Backup failed completely" >> /var/log/cron.log
    if [ -n "$NOTIFICATION" ]; then
        curl -X POST -F content="❌両方のストレージへのアップロードに失敗しました。" ${DISCORD_WEBHOOK_URL} &> /dev/null
    fi
fi

# ローカルファイルの削除
rm -f "$COMPRESSED"