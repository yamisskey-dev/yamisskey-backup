FROM debian:trixie-slim

ARG RCLONE_CONFIG_BACKUP_ENDPOINT
ARG RCLONE_CONFIG_BACKUP_ACCESS_KEY_ID
ARG RCLONE_CONFIG_BACKUP_SECRET_ACCESS_KEY
ARG RCLONE_CONFIG_BACKUP_BUCKET_ACL

# 必要なパッケージのインストール
RUN apt-get update && apt-get install -y \
    postgresql-client \
    p7zip-full \
    curl \
    bash \
    cron \
    procps \
    && rm -rf /var/lib/apt/lists/* \
    && curl https://rclone.org/install.sh | bash \
    && curl -sL https://filen.io/cli.sh | bash

# rclone設定
RUN mkdir -p /root/.config/rclone
COPY ./config/rclone.conf /root/.config/rclone/rclone.conf

# バックアップスクリプトの設定
RUN mkdir -p /opt/misskey-backup/backups
COPY ./src/backup.sh /usr/local/bin/misskey-backup
RUN chmod +x /usr/local/bin/misskey-backup

# cronジョブの設定
COPY ./config/crontab /etc/cron.d/misskey-backup
RUN chmod 0644 /etc/cron.d/misskey-backup \
    && chown root:root /etc/cron.d/misskey-backup \
    && echo "" >> /etc/cron.d/misskey-backup  # 空行を追加

# システムPATHの設定
RUN echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> /etc/environment

# ログファイルの設定
RUN touch /var/log/cron.log && chmod 0644 /var/log/cron.log

# cronを初期化して起動
CMD ["/bin/bash", "-c", "cron && tail -f /var/log/cron.log"]