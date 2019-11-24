#! /bin/bash
set -e

TARGET_USER=${1:-geniuser}
TARGET_GROUP=$(id -gn $TARGET_USER)
TARGET_HOME=$(eval echo "~$TARGET_USER")
CONFIG_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

make_dir() {
    mkdir -p $1
    sudo chown $TARGET_USER:$TARGET_GROUP $1
    sudo chmod 755 $1
}

link_files() {
    trap "$(shopt -p extglob)" RETURN
    shopt -s nullglob

    local base=$1
    local dst=$2
    local prefix=${3:-}

    echo "Link files from $base to $dst"
    make_dir "$dst"
    for dot in $base/*; do
        local tgt=$dst/$prefix${dot##*/}
        if [[ -d "$dot" ]]; then
            link_files "$dot" "$tgt"
        else
            echo "Link $dot -> $tgt"
            ln -sf $(realpath $dot) "$tgt"
        fi
    done
}

# whoami
echo "Running as $(whoami) with groups ($(groups)), targeting user $TARGET_USER:$TARGET_GROUP"

# i am root now
if [[ $EUID -ne 0 ]]; then
    echo "Escalating to root with sudo"
    exec sudo /bin/bash "$0" "$@"
fi

# am i done
if [[ -f /local/repository/.setup-done ]]; then
    exit
fi
date > /local/repository/.setup-done

# base software
sudo apt-get update
sudo apt-get install -y zsh fonts-powerline git tmux neovim python3-neovim build-essential cmake gawk htop
sudo apt-get autoremove -y

echo "Setting default shell to zsh"
sudo usermod -s /usr/bin/zsh $TARGET_USER
echo "Setting default editor to neovim"
for exe in vi vim editor; do
    sudo update-alternatives --install /usr/bin/$exe $exe /usr/bin/nvim 60
done

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

# update repo
echo "Updating profile repo"
if [[ -d /local/repository ]]; then
    cd /local/repository
    git checkout master
    git pull
fi

# dotfiles
echo "Linking dotfiles"
make_dir $TARGET_HOME/.local
link_files $CONFIG_DIR/dotfiles/home $TARGET_HOME "."
ln -sf $CONFIG_DIR/dotfiles/scripts $TARGET_HOME/.local/bin

# common directories
make_dir $TARGET_HOME/tools
make_dir $TARGET_HOME/downloads
make_dir $TARGET_HOME/buildbed

# python
echo "Setting up python"
curl -JOL 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh'
bash Miniconda3-latest-Linux-x86_64.sh -b -p $TARGET_HOME/tools/miniconda3
rm Miniconda3-latest-Linux-x86_64.sh
# make sure condarc is sourced even when not running as target user
export CONDARC=$TARGET_HOME/.condarc

$TARGET_HOME/tools/miniconda3/bin/conda install --yes pip ipython jupyter jupyterlab matplotlib ipdb
$TARGET_HOME/tools/miniconda3/bin/conda install --yes pytorch torchvision cudatoolkit=10.0 -c pytorch

# install project specific
if [[ -d /nfs/HpBandSter ]]; then
    $TARGET_HOME/tools/miniconda3/bin/pip install -e /nfs/HpBandSter/
fi

if [[ -d /nfs/Auto-PyTorch ]]; then
    $TARGET_HOME/tools/miniconda3/bin/pip install -r /nfs/Auto-PyTorch/requirements.txt
    $TARGET_HOME/tools/miniconda3/bin/pip install openml
    $TARGET_HOME/tools/miniconda3/bin/pip install -e /nfs/Auto-PyTorch/
fi

if [[ -d /nfs/cifar-automl ]]; then
    $TARGET_HOME/tools/miniconda3/bin/pip install hyperopt
fi

# fix permission
echo "Fixing permission"
chown -R $TARGET_USER:$TARGET_GROUP $TARGET_HOME
chown -R $TARGET_USER:$TARGET_GROUP /local/repository

# initialize vim as if on first login
su --login $TARGET_USER <<EOSU
zsh --login -c "echo Initialized zsh"
vim +PlugInstall! +qall
EOSU
