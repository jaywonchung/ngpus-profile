# Ansible managed

export NVM_DIR="$XDG_DATA_HOME/nvm"

# lazy loading nvm to avoid it slow down shell startup
# lazy loading the bash completions does not save us meaningful shell startup time, so we won't do it

# add our default nvm node (`nvm alias default 10.16.0`) to path without loading nvm
# see: https://gist.github.com/gfguthrie/9f9e3908745694c81330c01111a9d642#gistcomment-3143229
DEFAULT_NODE_VER='default'
while [ -s "$NVM_DIR/alias/$DEFAULT_NODE_VER" ]; do
  DEFAULT_NODE_VER="$(<$NVM_DIR/alias/$DEFAULT_NODE_VER)"
done;

uprepend path "$NVM_DIR/versions/node/v${DEFAULT_NODE_VER#v}/bin"
# alias `nvm` to this one liner lazy load of the normal nvm script
alias nvm="unalias nvm; [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"; nvm $@"
