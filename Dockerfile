FROM debian:trixie-slim

RUN apt-get update && apt-get install -y \
    postgresql-client \
    p7zip-full \
    curl \
    bash \
    cron \
    && rm -rf /var/lib/apt/lists/* \
    && curl https://rclone.org/install.sh | bash \
    && curl -sL https://filen.io/cli.sh | bash

RUN mkdir -p /root/.config/rclone
COPY ./config/rclone.conf /root/.config/rclone/rclone.conf
#COPY <<EOF /root/.config/rclone/rclone.conf
#[backup]
#type = s3
#provider = Cloudflare
#access_key_id = ${RCLONE_CONFIG_BACKUP_ACCESS_KEY_ID}
#secret_access_key = ${RCLONE_CONFIG_BACKUP_SECRET_ACCESS_KEY}
#region = auto
#endpoint = ${RCLONE_CONFIG_BACKUP_ENDPOINT}
#bucket_acl = ${RCLONE_CONFIG_BACKUP_BUCKET_ACL}
#EOF

# backup script
COPY ./src/backup.sh /root/
RUN chmod +x /root/backup.sh

RUN mkdir -p /opt/misskey-backup/backups

# crontab
RUN mkdir -p /var/spool/cron/crontabs
COPY ./config/crontab /var/spool/cron/crontabs/root
RUN chmod 0644 /var/spool/cron/crontabs/root

CMD sh -c "crond -l 0 -f"
