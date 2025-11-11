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

    # ファイルの存在確認
    if [ ! -f "$COMPRESSED" ]; then
        echo "Error: Backup file does not exist for R2 upload: $COMPRESSED" >> /var/log/cron.log
        return 1
    fi

    # ファイルサイズの確認
    filesize=$(stat -f%z "$COMPRESSED" 2>/dev/null || stat -c%s "$COMPRESSED" 2>/dev/null)
    echo "Backup file size for R2 upload: $filesize bytes" >> /var/log/cron.log

    # rcloneの設定確認
    echo "Checking rclone configuration..." >> /var/log/cron.log
    if ! rclone listremotes | grep -q "backup:"; then
        echo "Error: rclone backup remote is not configured" >> /var/log/cron.log
        return 1
    fi

    # R2バケットへのアクセス確認
    echo "Checking R2 bucket access..." >> /var/log/cron.log
    if ! rclone lsd backup: 2>> /var/log/cron.log; then
        echo "Error: Cannot access R2 bucket" >> /var/log/cron.log
        return 1
    fi

    # アップロード実行
    echo "Starting R2 upload process..." >> /var/log/cron.log
    if rclone copy --s3-upload-cutoff=5000M --multi-thread-cutoff 5000M --progress "$COMPRESSED" backup:${R2_PREFIX} 2>> /var/log/cron.log; then
        echo "R2 upload succeeded" >> /var/log/cron.log

        # アップロード後のファイル確認
        if rclone ls backup:${R2_PREFIX}/$(basename "$COMPRESSED") 2>> /var/log/cron.log; then
            echo "R2 upload verification succeeded" >> /var/log/cron.log
            return 0
        else
            echo "R2 upload verification failed - file not found in bucket" >> /var/log/cron.log
            return 1
        fi
    else
        echo "R2 upload failed with status $?" >> /var/log/cron.log
        return 1
    fi
}

# Linode Object Storageへのアップロード関数
upload_to_linode() {
    echo "Uploading to Linode Object Storage..." >> /var/log/cron.log

    # ファイルの存在確認
    if [ ! -f "$COMPRESSED" ]; then
        echo "Error: Backup file does not exist for Linode upload: $COMPRESSED" >> /var/log/cron.log
        return 1
    fi

    # ファイルサイズの確認
    filesize=$(stat -f%z "$COMPRESSED" 2>/dev/null || stat -c%s "$COMPRESSED" 2>/dev/null)
    echo "Backup file size for Linode upload: $filesize bytes" >> /var/log/cron.log

    # rcloneの設定確認
    echo "Checking rclone configuration..." >> /var/log/cron.log
    if ! rclone listremotes | grep -q "linode:"; then
        echo "Error: rclone linode remote is not configured" >> /var/log/cron.log
        return 1
    fi

    # Linodeバケットへのアクセス確認
    echo "Checking Linode bucket access..." >> /var/log/cron.log
    if ! rclone lsd linode:${LINODE_BUCKET} 2>> /var/log/cron.log; then
        echo "Error: Cannot access Linode bucket" >> /var/log/cron.log
        return 1
    fi

    # アップロード実行
    echo "Starting Linode upload process..." >> /var/log/cron.log
    if rclone copy --progress "$COMPRESSED" linode:${LINODE_BUCKET}/${LINODE_PREFIX} 2>> /var/log/cron.log; then
        echo "Linode upload succeeded" >> /var/log/cron.log

        # アップロード後のファイル確認
        if rclone ls linode:${LINODE_BUCKET}/${LINODE_PREFIX}/$(basename "$COMPRESSED") 2>> /var/log/cron.log; then
            echo "Linode upload verification succeeded" >> /var/log/cron.log
            return 0
        else
            echo "Linode upload verification failed - file not found in bucket" >> /var/log/cron.log
            return 1
        fi
    else
        echo "Linode upload failed with status $?" >> /var/log/cron.log
        return 1
    fi
}

# 両方のアップロードを実行
R2_SUCCESS=false
LINODE_SUCCESS=false

# R2へのアップロードを先に実行
upload_to_r2
if [ $? -eq 0 ]; then
    R2_SUCCESS=true
fi

# Linodeへのアップロード
upload_to_linode
if [ $? -eq 0 ]; then
    LINODE_SUCCESS=true
fi

# 結果の通知
if [ "$R2_SUCCESS" = true ] || [ "$LINODE_SUCCESS" = true ]; then
    echo "Backup partially or fully succeeded" >> /var/log/cron.log

    if [ -n "$NOTIFICATION" ]; then
        MESSAGE="✅バックアップが完了しました。(${COMPRESSED})\n"
        if [ "$R2_SUCCESS" = false ]; then
            MESSAGE+="⚠️ R2へのアップロードは失敗しました。\n"
        fi
        if [ "$LINODE_SUCCESS" = false ]; then
            MESSAGE+="⚠️ Linodeへのアップロードは失敗しました。\n"
        fi
        curl -X POST -F content="$MESSAGE" ${DISCORD_WEBHOOK_URL} &> /dev/null
    fi
else
    echo "Backup failed completely" >> /var/log/cron.log
    if [ -n "$NOTIFICATION" ]; then
        curl -X POST -F content="❌両方のストレージへのアップロードに失敗しました。" ${DISCORD_WEBHOOK_URL} &> /dev/null
    fi
fi

# 最後にローカルファイルを削除
if [ -f "$COMPRESSED" ]; then
    rm -f "$COMPRESSED"
    echo "Cleaned up local backup file" >> /var/log/cron.log
fi