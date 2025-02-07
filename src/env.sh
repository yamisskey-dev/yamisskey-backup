#!/bin/bash

# 環境変数ファイルから変数を読み込む
if [ -f /opt/misskey-backup/config/.env ]; then
    set -a
    source /opt/misskey-backup/config/.env
    set +a
fi