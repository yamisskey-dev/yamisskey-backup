FROM debian:trixie-slim

ARG RCLONE_CONFIG_BACKUP_ENDPOINT
ARG RCLONE_CONFIG_BACKUP_ACCESS_KEY_ID
ARG RCLONE_CONFIG_BACKUP_SECRET_ACCESS_KEY
ARG RCLONE_CONFIG_BACKUP_BUCKET_ACL

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

RUN mkdir -p /root/.config/rclone /opt/misskey-backup/backups

COPY ./config/rclone.conf /root/.config/rclone/rclone.conf
COPY ./src/backup.sh /root/
COPY ./config/crontab /etc/cron.d/backup-cron

# 正しい権限設定
RUN chmod +x /root/backup.sh && \
    chmod 0644 /etc/cron.d/backup-cron && \
    chown root:root /etc/cron.d/backup-cron

# ログファイルの設定
RUN touch /var/log/cron.log && \
    chmod 0644 /var/log/cron.log

# PATHの設定
RUN echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> /etc/environment

# 新しいcrontab設定方法
RUN crontab /etc/cron.d/backup-cron

CMD ["cron", "-f"]