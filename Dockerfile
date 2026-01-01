FROM debian:trixie-slim

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
    && rm -rf /var/lib/apt/lists/* \
    && curl https://rclone.org/install.sh | bash

# rclone設定ディレクトリ（設定は entrypoint.sh で環境変数から生成）
RUN mkdir -p /root/.config/rclone

# バックアップスクリプトの設定
RUN mkdir -p /opt/misskey-backup/backups
COPY ./backup.sh /usr/local/bin/misskey-backup
RUN chmod +x /usr/local/bin/misskey-backup

# エントリーポイントスクリプト（rclone設定とcronジョブを環境変数から生成）
COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# システムPATHの設定
RUN echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> /etc/environment

# ログファイルの設定
RUN touch /var/log/cron.log && chmod 0644 /var/log/cron.log

# エントリーポイントの設定
ENTRYPOINT ["/entrypoint.sh"]