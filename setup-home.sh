#! /bin/bash
set -ex

SELF_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
CONFIG_DIR="$SELF_DIR"

make_dir() {
    mkdir -p $1
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
            ln -sfn $(realpath $dot) "$tgt"
        fi
    done
}

# per user configs
config_user() {
    local TARGET_USER=$1
    local TARGET_GROUP=$(id -gn $TARGET_USER)
    local TARGET_HOME=$(eval echo "~$TARGET_USER")

    if [[ -f $TARGET_HOME/.setup-done ]]; then
        return
    fi

    echo "Configuring $TARGET_USER"

    echo "Setting default shell to zsh"
    sudo usermod -s /usr/bin/zsh $TARGET_USER

    # dotfiles
    echo "Linking dotfiles"
    make_dir $TARGET_HOME/.local
    link_files $CONFIG_DIR/dotfiles/home $TARGET_HOME "."
    ln -sf $CONFIG_DIR/dotfiles/scripts $TARGET_HOME/.local/bin

    # common directories
    make_dir $TARGET_HOME/tools
    make_dir $TARGET_HOME/downloads
    make_dir $TARGET_HOME/buildbed

    # fix mounting point
    if [[ -d $TARGET_HOME/my_mounting_point ]]; then
        sudo umount $TARGET_HOME/my_mounting_point
    fi

    # fix permission
    echo "Fixing permission"
    sudo chown -R $TARGET_USER:$TARGET_GROUP $TARGET_HOME

    # initialize vim as if on first login
    sudo su --login $TARGET_USER <<EOSU
zsh --login -c "umask 022 && source \$HOME/.zshrc && echo Initialized zsh" &
nvim --headless +PlugInstall! +qall > /dev/null
wait
EOSU

    date > $TARGET_HOME/.setup-done
}

sudo git -C $SELF_DIR pull

for user in "$@"
do
    config_user "$user"
done
