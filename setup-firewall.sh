#! /bin/bash
set -ex

# Log output of this script to syslog.
# https://urbanautomaton.com/blog/2014/09/09/redirecting-bash-script-output-to-syslog/
exec 1> >(logger -s -t $(basename $0)) 2>&1

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
        echo "Updated successfully, reexec"
        exec "$0" "$@"
    else
        echo "Up-to-date"
    fi
fi

# Setup firewall
echo "Setup firewall"
apt-get update && apt-get install -y firewalld
firewall-cmd --zone=trusted --add-source=192.168.0.0/16
firewall-cmd --runtime-to-permanent
