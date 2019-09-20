#! /bin/bash
set -e

if [[ -f /local/repository/.setup-done ]]; then
    exit
fi
touch /local/repository/.setup-done

TARGET_USER=${1:-peifeng}
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

# base software
sudo apt-get update
sudo apt-get install -y zsh fonts-powerline git tmux neovim python3-neovim

echo "Set default shell to zsh"
sudo usermod -s /usr/bin/zsh $TARGET_USER
echo "Set default editor to neovim"
for exe in vi vim editor; do
    sudo update-alternatives --install /usr/bin/$exe $exe /usr/bin/nvim 60
done

# update repo
if [[ -d /local/repository ]]; then
    cd /local/repository
    git checkout master
    git pull
fi

# dotfiles
make_dir $TARGET_HOME/.local
link_files $CONFIG_DIR/dotfiles/home $TARGET_HOME "."
ln -sf $CONFIG_DIR/dotfiles/scripts $TARGET_HOME/.local/bin

# common directories
make_dir $TARGET_HOME/tools
make_dir $TARGET_HOME/downloads
make_dir $TARGET_HOME/buildbed

# python
curl -JOL 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh'
bash Miniconda3-latest-Linux-x86_64.sh -b -p $TARGET_HOME/tools/miniconda3
rm Miniconda3-latest-Linux-x86_64.sh
$TARGET_HOME/tools/miniconda3/bin/conda install --yes pip pytorch

# install project specific
$TARGET_HOME/tools/miniconda3/bin/pip install -r /proj/gaia-PG0/peifeng/automl/Auto-PyTorch/requirements.txt
