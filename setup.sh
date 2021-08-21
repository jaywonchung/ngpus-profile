#! /bin/bash
set -ex

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
    git remote update && git status -uno | grep -q 'Profile repo branch is behind' && changed=true
    if $changed; then
        git pull
        echo "Updated successfully, reexec setup.sh"
        exec /local/repository/setup.sh
    else
        echo "Up-to-date"
    fi
fi

# am i done
if [[ -f /local/repository/.setup-done ]]; then
    exit
fi

# mount /tmp as tmpfs
mount -t tmpfs tmpfs /tmp

# mount /opt from /data
mkdir -p /data/opt && mount --bind /data/opt /opt

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
apt-get install -y zsh fonts-powerline git git-lfs tmux neovim python3-neovim build-essential cmake gawk htop bmon jq
apt-get autoremove -y

# docker
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# cuda driver
if lspci | grep -q -i nvidia; then
    apt-get install -y nvidia-headless-470-server nvidia-utils-470-server

    modprobe -r nouveau || true
    modprobe nvidia || true

    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list > /etc/apt/sources.list.d/nvidia-docker.list
    apt-get update
    apt-get install -y nvidia-docker2
    # add gpu as generic resource on node
    nvidia-smi --query-gpu=uuid --format=csv,noheader | while read uuid ; do
        jq --arg value "gpu=$uuid" '."node-generic-resources" |= . + [$value]' < /etc/docker/daemon.json > tmp.$$.json && mv tmp.$$.json /etc/docker/daemon.json
    done
    jq '. + { "default-runtime": "nvidia" }' < /etc/docker/daemon.json > tmp.$$.json && mv tmp.$$.json /etc/docker/daemon.json
fi

# daemon config file after possible installation of cuda driver, as that may change this file
jq '. + { "data-root": "/data/docker-data" }' < /etc/docker/daemon.json > tmp.$$.json && mv tmp.$$.json /etc/docker/daemon.json
systemctl restart docker

# additional software
curl -s https://api.github.com/repos/BurntSushi/ripgrep/releases/latest |
    grep -oP "browser_download_url.*\Khttp.*amd64.deb" |
    xargs -n 1 curl -JL -o install.deb &&
    dpkg -i install.deb &&
    rm install.deb
curl -s https://api.github.com/repos/sharkdp/fd/releases/latest |
    grep -oP "browser_download_url.*\Khttp.*amd64.deb" |
    xargs -n 1 curl -JL -o install.deb &&
    dpkg -i install.deb &&
    rm install.deb
# pueued
curl -s https://api.github.com/repos/Nukesor/pueue/releases/latest |
    grep -oP "browser_download_url.*\Khttp.*pueue-linux-amd64" |
    xargs -n 1 curl -JL -o pueue &&
    install -D pueue /usr/local/bin/pueue &&
    rm pueue
curl -s https://api.github.com/repos/Nukesor/pueue/releases/latest |
    grep -oP "browser_download_url.*\Khttp.*pueued-linux-amd64" |
    xargs -n 1 curl -JL -o pueued &&
    install -D pueued /usr/local/bin/pueued &&
    rm pueued
curl -s https://api.github.com/repos/Nukesor/pueue/releases/latest |
    grep -oP "tarball_url.*\Khttp.*tarball/v[^\"]*" |
    xargs -n 1 curl -JL |
    tar xzf - --strip-components=2 --wildcards '*/utils/pueued.service' &&
    sed -i "s#/usr/bin#/usr/local/bin#g" pueued.service &&
    install -Dm644 pueued.service /etc/systemd/user/pueued.service &&
    rm pueued.service &&
    systemctl --user --global enable pueued
# procs
curl -s https://api.github.com/repos/dalance/procs/releases/latest |
    grep -oP "browser_download_url.*\Khttp.*x86_64-lnx.zip" |
    xargs -n 1 curl -JL -o install.zip &&
    unzip -o -d /usr/local/bin install.zip &&
    rm install.zip

echo "Setting default editor to neovim"
for exe in vi vim editor; do
    update-alternatives --install /usr/bin/$exe $exe /usr/bin/nvim 60
done

echo "Setting default umask"
sed -i -E 's/^(UMASK\s+)[0-9]+$/\1002/g' /etc/login.defs

# python
echo "Setting up python"
CONDA_PREFIX=/opt/miniconda3
curl -JOL 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh'
rm -rf "$CONDA_PREFIX"
bash Miniconda3-latest-Linux-x86_64.sh -b -p $CONDA_PREFIX
rm Miniconda3-latest-Linux-x86_64.sh
cat <<CONDARC > $CONDA_PREFIX/condarc
auto_activate_base: true
channel_priority: strict
channels:
  - pytorch
  - conda-forge
  - defaults
CONDARC

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
$CONDA_PREFIX/bin/conda install --yes pip ipython jupyter jupyterlab matplotlib cython
#$CONDA_PREFIX/bin/conda install --yes pytorch=1.5.0 torchvision cudatoolkit=10.2 -c pytorch
# make sure everyone can install
chgrp -R $PROJ_GROUP /opt/miniconda3
chmod -R g+w /opt/miniconda3

# install project specific
if [[ -d /nfs/HpBandSter ]]; then
    $CONDA_PREFIX/bin/pip install -e /nfs/HpBandSter/
fi

if [[ -d /nfs/Auto-PyTorch ]]; then
    $CONDA_PREFIX/bin/pip install -r /nfs/Auto-PyTorch/requirements.txt
    $CONDA_PREFIX/bin/pip install openml
    $CONDA_PREFIX/bin/pip install -e /nfs/Auto-PyTorch/
fi

if [[ -d /nfs/cifar-automl ]]; then
    $CONDA_PREFIX/bin/pip install hyperopt
fi

# setup homes
$SELF_DIR/setup-home.sh "$@"

date > /local/repository/.setup-done
