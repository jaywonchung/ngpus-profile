#!/bin/bash

set -ex

# Log output of this script to syslog.
# https://urbanautomaton.com/blog/2014/09/09/redirecting-bash-script-output-to-syslog/
exec 1> >(logger -s -t $(basename $0)) 2>&1

# is this after a reboot?
# nvidia-smi
# if [ "$?" = "0"]; then
#   exit
# fi

PROJ_GROUP=gaia-PG0
SELF_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# whoami
echo "Running as $(whoami) with groups ($(groups))"

# i am root now
if [[ $EUID -ne 0 ]]; then
    echo "Escalating to root with sudo"
    exec sudo /bin/bash "$0" "$@"
fi

# update repo
echo "Updating profile repo"
if [[ -d /local/repository ]]; then
    cd /local/repository
    chgrp -R $PROJ_GROUP /local/repository
    chmod -R g+w /local/repository
    git checkout master

    changed=false
    git remote update && git status -uno | grep -q 'branch is behind' && changed=true
    if $changed; then
        git pull
        echo "Updated successfully, reexec $0"
        exec "$0"
    else
        echo "Up-to-date"
    fi
fi

# am i done
if [[ -f /local/repository/.setup-done ]]; then
    exit
fi

# mount /tmp as tmpfs
cat > /etc/systemd/system/tmp.mount <<EOF
[Unit]
Description=Temporary Directory /tmp

[Mount]
What=tmpfs
Where=/tmp
Type=tmpfs
Options=mode=1777,strictatime,nosuid,nodev,size=50%,nr_inodes=400k

[Install]
WantedBy=local-fs.target
EOF
systemctl daemon-reload && systemctl enable --now tmp.mount

# although we now mount 200G to / directly, we create a /data for compatibility
mkdir -p /data

# mount /opt from /data
cat > /etc/systemd/system/opt.mount <<EOF
[Unit]
Description=Bind /opt to /data/opt

[Mount]
What=/data/opt
Where=/opt
Type=none
Options=bind

[Install]
WantedBy=local-fs.target
EOF
systemctl daemon-reload && systemctl enable --now opt.mount

# fix /data permission
chgrp -R $PROJ_GROUP /data
chmod -R g+sw /data

# fix /nfs permission
chgrp -R $PROJ_GROUP /nfs
chmod -R g+sw /nfs

# remove unused PPAs
find /etc/apt/sources.list.d/ -type f -print -delete

# base software
apt-get update
apt-get install -y zsh git tmux build-essential cmake htop
apt-get autoremove -y

# cuda driver
if lspci | grep -q -i nvidia; then
    apt-get purge -y nvidia* libnvidia*
    apt-get install -y nvidia-headless-470-server nvidia-utils-470-server

    modprobe -r nouveau || true
    modprobe nvidia || true
fi

echo "Setting default umask"
sed -i -E 's/^(UMASK\s+)[0-9]+$/\1002/g' /etc/login.defs

# setup home
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

# fix mounting point
if [[ -d $TARGET_HOME/my_mounting_point ]]; then
    umount $TARGET_HOME/my_mounting_point
fi

# fix permission
echo "Fixing permission"
chown -R $TARGET_USER:$TARGET_GROUP $TARGET_HOME

TZ='America/Detroit' date > /local/repository/.setup-done

# for nvidia driver
reboot
