# Alias
alias ls='ls --ignore=lost+found --color=auto -h -v --indicator-style=classify'
alias ll='ls -l'
alias la='ls -a'
alias lla='ls -al'
alias bd=". bd -si"
alias kfg="kill -- -\$(jobs -p); fg"
function cdmk() {
    mkdir -p "$@"
    cd $1
}
function htop() {
    local htoprc=$HOME/.config/htop/htoprc.low
    if [[ $(tput lines) -gt 50 ]]; then
        htoprc=$HOME/.config/htop/htoprc.high
    fi
    env TERM=screen HTOPRC=$htoprc htop "$@"
}
