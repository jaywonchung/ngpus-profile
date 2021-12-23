#!/bin/bash

set -ex

# Log output of this script to syslog.
# https://urbanautomaton.com/blog/2014/09/09/redirecting-bash-script-output-to-syslog/
exec 1> >(logger -s -t $(basename $0)) 2>&1

PROJ_GROUP="$2"

# whoami
echo "Running as $(whoami) with groups ($(groups))"

# i am root now
if [[ $EUID -ne 0 ]]; then
  echo "Escalating to root with sudo"
  exec sudo /bin/bash "$0" "$@"
fi

# am i done
if [[ -f /.setup-done ]]; then
  echo "Found /.setup-done, exit."
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
apt-get install -y zsh git tmux build-essential htop apt-transport-https ca-certificates curl gnupg lsb-release
apt-get autoremove -y

# latest cmake
wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | sudo tee /etc/apt/trusted.gpg.d/kitware.gpg > /dev/null
apt-add-repository "deb https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main"
apt-get update
apt-get install -y kitware-archive-keyring
rm /etc/apt/trusted.gpg.d/kitware.gpg
apt-get install -y cmake

# docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --batch --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# cuda driver
if lspci | grep -q -i nvidia; then
  apt-get purge -y nvidia* libnvidia*
  apt-get install -y nvidia-headless-470-server nvidia-utils-470-server

  modprobe -r nouveau || true
  modprobe nvidia || true
fi

# nvidia-docker
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list > /etc/apt/sources.list.d/nvidia-docker.list
apt-get update
apt-get install -y nvidia-docker2
(cat /etc/docker/daemon.json 2>/dev/null || echo "{}") | jq '. + { "default-runtime": "nvidia" }' > tmp.$$.json && mv tmp.$$.json /etc/docker/daemon.json
# add gpu as generic resource on node
nvidia-smi --query-gpu=uuid --format=csv,noheader | while read uuid ; do
    jq --arg value "gpu=$uuid" '."node-generic-resources" |= . + [$value]' < /etc/docker/daemon.json > tmp.$$.json && mv tmp.$$.json /etc/docker/daemon.json
done

# use /data/docker-data as docker data root directory
(cat /etc/docker/daemon.json 2>/dev/null || echo "{}") | jq '. + { "data-root": "/data/docker-data" }' > tmp.$$.json && mv tmp.$$.json /etc/docker/daemon.json
systemctl restart docker

# fix docker directory permission
chown -R root.root /data/docker-data
chmod -R g-s /data/docker-data

# block traffic to docker containers
firewall-cmd --zone=docker --set-target=default --permanent
firewall-cmd --reload
systemctl restart docker

# miniconda
CONDA_PREFIX=/opt/miniconda3
curl -JOL 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh'
rm -rf "$CONDA_PREFIX"
bash Miniconda3-latest-Linux-x86_64.sh -b -p $CONDA_PREFIX
rm Miniconda3-latest-Linux-x86_64.sh
if ! grep 'conda_setup' /etc/zsh/zshenv; then
  cat <<EOF >> /etc/zsh/zshenv
__conda_setup="\$('/opt/miniconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ \$? -eq 0 ]; then
    eval "\$__conda_setup"
else
    if [ -f "/opt/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/opt/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/opt/miniconda3/bin:\$PATH"
    fi
fi
EOF
fi
ln -sf $CONDA_PREFIX/etc/profile.d/conda.sh /etc/profile.d

# make sure everyone can install
chgrp -R $PROJ_GROUP $CONDA_PREFIX
chmod -R g+w $CONDA_PREFIX

echo "Setting default umask"
sed -i -E 's/^(UMASK\s+)[0-9]+$/\1002/g' /etc/login.defs

# setup home
SELF_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
$SELF_DIR/setup-home.sh "$@"

# setup done
TZ='America/Detroit' date > /.setup-done

# for nvidia driver
reboot
