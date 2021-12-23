#!/bin/bash
set -ex

# Log output of this script to syslog.
# https://urbanautomaton.com/blog/2014/09/09/redirecting-bash-script-output-to-syslog/
exec 1> >(logger -s -t $(basename $0)) 2>&1

# whoami
echo "Running as $(whoami) with groups ($(groups))"

# i am root now
if [[ $EUID -ne 0 ]]; then
    echo "Escalating to root with sudo"
    exec sudo /bin/bash "$0" "$@"
fi

# Setup firewall
echo "Setup firewall"
apt-get update && apt-get install -y firewalld
firewall-cmd --zone=trusted --add-source=192.168.0.0/16
firewall-cmd --runtime-to-permanent

echo "Successfully setup firewall. Exiting."
