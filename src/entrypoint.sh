#!/bin/bash

# 環境変数を含むcrontabファイルを生成
envsubst < /etc/cron.d/crontab.template > /etc/cron.d/misskey-backup

# crontabファイルのパーミッションを設定
chmod 0644 /etc/cron.d/misskey-backup

# cronを起動してログを監視
cron && tail -f /var/log/cron.log