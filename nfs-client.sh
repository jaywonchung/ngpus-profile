#!/bin/bash
#
# Setup NFS client and mount server.
#
# This script is derived from Jonathan Ellithorpe's Cloudlab profile at
# https://github.com/jdellithorpe/cloudlab-generic-profile. Thanks!
#
# Hacked by mike to work on FreeBSD. The whole strategy has been changed
# however. Rather than insert commands/variables into the standard system
# files to have every thing restart on reboot via the standard mechanisms,
# we handle all the startup from this script. This is because the standard
# mechanisms run well before the Emulab scripts have configured the
# experimental LAN we are serving files on. On the other hand, this script
# runs at the end of the Emulab scripts. I do not know how the old method
# worked even on Linux when there was a reboot!
#
. /etc/emulab/paths.sh

#
# Export the original username and group
# and then escalate as root
#
export ORIG_USER=$USER
export ORIG_GROUP=$(id -gn $USER)

if [[ $EUID -ne 0 ]]; then
    echo "Escalating to root with sudo"
    exec sudo /bin/bash "$0" "$@"
fi


OS=$(uname -s)
HOSTNAME=$(hostname -s)

#
# The storage partition is mounted on /nfs, if you change this, you
# must change profile.py also.
#
NFSDIR="/nfs"

#
# The name of the nfs server. If you change these, you have to
# change profile.py also.
#
NFSNETNAME="nfsLan"
NFSSERVER="nfs-$NFSNETNAME"

#
# The name of the "prepare" for image snapshot hook.
#
HOOKNAME="$BINDIR/prepare.pre.d/nfs-client.sh"

if ! (grep -q $NFSSERVER /etc/hosts); then
    echo "$NFSSERVER is not in /etc/hosts"
    exit 1
fi

#
# On Linux, see if the packages are installed
#
if [ "$OS" = "Linux" ]; then
    # === Software dependencies that need to be installed. ===
    apt-get update
    stat=`dpkg-query -W -f '${DB:Status-Status}\n' nfs-common`
    if [ "$stat" = "not-installed" ]; then
	echo ""
	echo "Installing NFS packages"
	apt-get --assume-yes install nfs-common
    fi
fi

# Wait until nfs is properly set up.
while ! (rpcinfo -s $NFSSERVER | grep -q nfs); do
    echo ""
    echo "Waiting for NFS server $NFSSERVER ..."
    sleep 2
done

# Create the local mount directory.
if [ ! -e $NFSDIR ]; then
    mkdir -p -m 2755 $NFSDIR
    chown $ORIG_USER:$ORIG_GROUP $NFSDIR
fi

mntopts=
if [ "$OS" = "Linux" ]; then
    mntopts="rw,bg,sync,hard,intr"
else
    mntopts="nfsv3,tcp,rw,bg,hard,intr"
fi

#
# Run the mount. It is a background mount, so will keep trying until
# the server is up, which it already should be,
#
echo ""
echo "Mounting $NFSSERVER:$NFSDIR ..."
if ! mount -t nfs -o $mntopts $NFSSERVER:$NFSDIR $NFSDIR; then
    echo 'WARNING: Background mount failed?! Trying again in 5 seconds ...'
    sleep 5
    if ! mount -t nfs -o $mntopts $NFSSERVER:$NFSDIR $NFSDIR; then
	echo 'FATAL: Background mount failed?! Giving up.'
	exit 1
    fi
fi

#
# But do not exit until the mount is made, in case there is another
# script after this one, that depends on the mount really being there.
#
if [ "$OS" = "Linux" ]; then
    while ! (findmnt $NFSDIR); do
	echo "Waiting for NFS mount of $NFSDIR ..."
	sleep 2
    done
else
    while ! mount | grep -q "^$NFSSERVER:$NFSDIR"; do
	echo "Waiting for NFS mount of $NFSDIR ..."
	sleep 2
    done
fi

echo ""
echo "Mount of $NFSSERVER:$NFSDIR is ready."
exit 0
