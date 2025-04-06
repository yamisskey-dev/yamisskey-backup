FROM debian:trixie-slim

ARG RCLONE_CONFIG_BACKUP_ENDPOINT
ARG RCLONE_CONFIG_BACKUP_ACCESS_KEY_ID
ARG RCLONE_CONFIG_BACKUP_SECRET_ACCESS_KEY
ARG RCLONE_CONFIG_BACKUP_BUCKET_ACL

# タイムゾーンの設定
ENV TZ=Asia/Tokyo
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone

# 必要なパッケージのインストール
RUN apt-get update && apt-get install -y \
    postgresql-client \
    p7zip-full \
    curl \
    bash \
    cron \
    procps \
    gettext-base \
    libsecret-1-dev \
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

# 環境変数をcronに渡すためのエントリーポイントスクリプト
COPY ./src/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# cronジョブの設定（テンプレートとして）
COPY ./config/crontab.template /etc/cron.d/crontab.template

# システムPATHの設定
RUN echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> /etc/environment

# ログファイルの設定
RUN touch /var/log/cron.log && chmod 0644 /var/log/cron.log

# エントリーポイントの設定
ENTRYPOINT ["/entrypoint.sh"]