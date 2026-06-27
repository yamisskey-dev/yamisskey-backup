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

# B2用の固定ファイル名（日付なし）。毎回同名で上書きし、旧バージョンを
# B2のLifecycle（Keep prior versions）に世代管理させる。
# R2は従来通り COMPRESSED の日付入り名でアップロードする。
B2_OBJECT="${POSTGRES_DB}.sql.7z"

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
    if ! rclone listremotes | grep -q "r2:"; then
        echo "Error: rclone r2 remote is not configured" >> /var/log/cron.log
        return 1
    fi

    # R2バケットへのアクセス確認
    echo "Checking R2 bucket access..." >> /var/log/cron.log
    if ! rclone lsd r2: 2>> /var/log/cron.log; then
        echo "Error: Cannot access R2 bucket" >> /var/log/cron.log
        return 1
    fi

    # アップロード実行
    echo "Starting R2 upload process..." >> /var/log/cron.log
    if rclone copy --s3-upload-cutoff=5000M --multi-thread-cutoff 5000M --progress "$COMPRESSED" r2:${R2_PREFIX} 2>> /var/log/cron.log; then
        echo "R2 upload succeeded" >> /var/log/cron.log

        # アップロード後のファイル確認
        if rclone ls r2:${R2_PREFIX}/$(basename "$COMPRESSED") 2>> /var/log/cron.log; then
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

# Backblaze B2へのアップロード関数
upload_to_b2() {
    echo "Uploading to Backblaze B2..." >> /var/log/cron.log

    # ファイルの存在確認
    if [ ! -f "$COMPRESSED" ]; then
        echo "Error: Backup file does not exist for B2 upload: $COMPRESSED" >> /var/log/cron.log
        return 1
    fi

    # ファイルサイズの確認
    filesize=$(stat -f%z "$COMPRESSED" 2>/dev/null || stat -c%s "$COMPRESSED" 2>/dev/null)
    echo "Backup file size for B2 upload: $filesize bytes" >> /var/log/cron.log

    # rcloneの設定確認
    echo "Checking rclone configuration..." >> /var/log/cron.log
    if ! rclone listremotes | grep -q "b2:"; then
        echo "Error: rclone b2 remote is not configured" >> /var/log/cron.log
        return 1
    fi

    # B2バケットへのアクセス確認
    echo "Checking B2 bucket access..." >> /var/log/cron.log
    if ! rclone lsd b2: 2>> /var/log/cron.log; then
        echo "Error: Cannot access B2 bucket" >> /var/log/cron.log
        return 1
    fi

    # アップロード実行（固定ファイル名で上書き → 旧バージョンはB2のLifecycleで世代管理）
    echo "Starting B2 upload process..." >> /var/log/cron.log
    if rclone copyto --progress "$COMPRESSED" "b2:${B2_BUCKET}/${B2_PREFIX}/${B2_OBJECT}" 2>> /var/log/cron.log; then
        echo "B2 upload succeeded" >> /var/log/cron.log

        # アップロード後のファイル確認
        if rclone ls "b2:${B2_BUCKET}/${B2_PREFIX}/${B2_OBJECT}" 2>> /var/log/cron.log; then
            echo "B2 upload verification succeeded" >> /var/log/cron.log
            return 0
        else
            echo "B2 upload verification failed - file not found in bucket" >> /var/log/cron.log
            return 1
        fi
    else
        echo "B2 upload failed with status $?" >> /var/log/cron.log
        return 1
    fi
}

# 両方のアップロードを実行
R2_SUCCESS=false
B2_SUCCESS=false

# R2へのアップロードを先に実行
upload_to_r2
if [ $? -eq 0 ]; then
    R2_SUCCESS=true
fi

# B2へのアップロード
upload_to_b2
if [ $? -eq 0 ]; then
    B2_SUCCESS=true
fi

# 結果の通知
if [ "$R2_SUCCESS" = true ] || [ "$B2_SUCCESS" = true ]; then
    echo "Backup partially or fully succeeded" >> /var/log/cron.log

    if [ -n "$NOTIFICATION" ]; then
        MESSAGE="✅バックアップが完了しました。(${COMPRESSED})\n"
        if [ "$R2_SUCCESS" = false ]; then
            MESSAGE+="⚠️ R2へのアップロードは失敗しました。\n"
        fi
        if [ "$B2_SUCCESS" = false ]; then
            MESSAGE+="⚠️ B2へのアップロードは失敗しました。\n"
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