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

# am i done
if [[ -f /local/repository/.setup-done ]]; then
    exit
fi

# mount /tmp as tmpfs
mount -t tmpfs tmpfs /tmp

# remove unused PPAs
find /etc/apt/sources.list.d/ -type f -print -delete

# base software
sudo apt-get update
sudo apt-get install -y zsh fonts-powerline git tmux neovim python3-neovim build-essential cmake gawk htop bmon
sudo apt-get autoremove -y

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
    unzip -d /usr/local/bin install.zip &&
    rm install.zip

# mongodb on node-1
if [[ $(hostname) == node-1* ]]; then
    wget -qO - https://www.mongodb.org/static/pgp/server-4.2.asc | sudo apt-key add -
    echo "deb [ arch=amd64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/4.2 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.2.list
    sudo apt-get update
    sudo apt-get install -y mongodb-org

    vlan=$(basename $(find /sys/class/net -iname 'vlan*'))
    ip=$(ip a show dev $vlan | rg -Po 'inet \K\d+\.\d+\.\d+\.\d+')

    sed -i -E 's/(\s*bindIp:\s).*/\1'"$ip"'/g' /etc/mongod.conf

    sudo systemctl enable --now mongod
fi

echo "Setting default editor to neovim"
for exe in vi vim editor; do
    sudo update-alternatives --install /usr/bin/$exe $exe /usr/bin/nvim 60
done

echo "Setting default umask"
sed -i -E 's/^(UMASK\s+)[0-9]+$/\1002/g' /etc/login.defs

# update repo
echo "Updating profile repo"
if [[ -d /local/repository ]]; then
    cd /local/repository
    git checkout master
    git pull
    chgrp -R $PROJ_GROUP /local/repository
    chmod -R g+w /local/repository
fi

# python
echo "Setting up python"
CONDA_PREFIX=/opt/miniconda3
curl -JOL 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh'
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
ln -sf $CONDA_PREFIX/etc/profile.d/conda.sh /etc/profile.d
$CONDA_PREFIX/bin/conda install --yes pip ipython jupyter jupyterlab matplotlib cython
$CONDA_PREFIX/bin/conda install --yes pytorch=1.5.0 torchvision cudatoolkit=10.2 -c pytorch
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
$SELF_DIR/setup-home.sh peifeng JIACHEN

date > /local/repository/.setup-done
