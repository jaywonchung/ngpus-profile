#!/bin/bash

set -ex

# Log output of this script to syslog.
# https://urbanautomaton.com/blog/2014/09/09/redirecting-bash-script-output-to-syslog/
exec 1> >(logger -s -t $(basename $0)) 2>&1

TARGET_USER=$1
TARGET_GROUP=$(id -gn $TARGET_USER)
TARGET_HOME=$(eval echo "~$TARGET_USER")

echo "Configuring $TARGET_USER"

echo "Redirect cache to /data"
mount_unit=$(systemd-escape --path --suffix=mount $TARGET_HOME/.cache)
cat > /etc/systemd/system/$mount_unit <<EOF
[Unit]
Description=Bind $TARGET_HOME/.cache to /data/cache/$TARGET_USER

[Mount]
What=/data/cache/$TARGET_USER
Where=$TARGET_HOME/.cache
Type=none
Options=bind

[Install]
WantedBy=default.target
EOF
systemctl daemon-reload && systemctl enable --now $mount_unit

# change default shell to zsh
chsh -s $(which zsh) $TARGET_USER

# add user to docker group
usermod -aG docker $TARGET_USER

# fix my_mounting_point
if [[ -e "$TARGET_HOME/my_mounting_point" ]]; then
  umount "$TARGET_HOME/my_mounting_point"
  rm -rf "$TARGET_HOME/my_mounting_point"
fi

# fix permission
echo "Fixing permission"
chown -R $TARGET_USER:$TARGET_GROUP $TARGET_HOME
