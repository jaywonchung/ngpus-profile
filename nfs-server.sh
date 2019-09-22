#!/bin/bash
#
# Setup a simple FreeBSD NFS server on /nfs
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
# The name of the nfs network. If you change this, you must change
# profile.py also.
#
NFSNETNAME="nfsLan"

#
# The name of the "prepare" for image snapshot hook.
#
HOOKNAME="$BINDIR/prepare.pre.d/nfs-server.sh"

if ! (grep -q $HOSTNAME-$NFSNETNAME /etc/hosts); then
    echo "$HOSTNAME-$NFSNETNAME is not in /etc/hosts"
    exit 1
fi

#
# On Linux, see if the packages are installed
#
if [ "$OS" = "Linux" ]; then
    # === Software dependencies that need to be installed. ===
    apt-get update
    stat=`dpkg-query -W -f '${DB:Status-Status}\n' nfs-kernel-server`
    if [ "$stat" = "not-installed" ]; then
	echo ""
	echo "Installing NFS packages"
	apt-get --assume-yes install nfs-kernel-server nfs-common
	# make sure the server is not running til we fix up exports
	service nfs-kernel-server stop
    fi
fi

#
# If exports entry already exists, no need to do anything.
#
if ! grep -q "^$NFSDIR" /etc/exports; then
    # Will be owned by geniuser/gaia-PG0
    mkdir -p -m 2775 $NFSDIR
    chown $ORIG_USER:$ORIG_GROUP $NFSDIR

    echo ""
    echo "Setting up NFS exports"
    #
    # Export the NFS server directory to the subnet so that all clients
    # can mount it.  To do that, we need the subnet. Grab that from
    # /etc/hosts, and assume a netmask of 255.255.255.0, which will be
    # fine 99.9% of the time.
    #
    NFSIP=`grep -i $HOSTNAME-$NFSNETNAME /etc/hosts | awk '{print $1}'`
    NFSNET=`echo $NFSIP | awk -F. '{printf "%s.%s.%s.0", $1, $2, $3}'`

    if [ "$OS" = "Linux" ]; then
	echo "$NFSDIR $NFSNET/24(rw,sync,no_root_squash,no_subtree_check,fsid=0)" >> /etc/exports
    else
	echo "$NFSDIR -network $NFSNET -mask 255.255.255.0 -maproot=root -alldirs" >> /etc/exports
    fi

    if [ "$OS" = "Linux" ]; then
	# Make sure we start RPCbind to listen on the right interfaces.
	echo "OPTIONS=\"-l -h 127.0.0.1 -h $NFSIP\"" > /etc/default/rpcbind

	# We want to allow rpcinfo to operate from the clients.
	sed -i.bak -e "s/^rpcbind/#rpcbind/" /etc/hosts.deny
    else
	# On FreeBSD we will start all the services manually
	# But make sure the options are correct
	cp -p /etc/rc.conf /etc/rc.conf.bak
	cat <<EOF >> /etc/rc.conf
rpcbind_enable="NO"
rpcbind_flags="-h $NFSIP"
rpc_lockd_enable="NO"
rpc_lockd_flags="-h $NFSIP"
rpc_statd_enable="NO"
rpc_statd_flags="-h $NFSIP"
mountd_enable="NO"
mountd_flags="-h $NFSIP"
nfs_server_enable="NO"
nfs_server_flags="-u -t -h $NFSIP"
nfs_reserved_port_only="YES"
EOF
    fi
fi

#
# Create prepare hook to remove our customizations before we take the
# image snapshot. They will get reinstalled at reboot after image snapshot.
# Remove the hook script too, we do not want it in the new image, and
# it will get recreated as well at reboot.
#
if [ ! -e $HOOKNAME ]; then
    if [ "$OS" = "Linux" ]; then
	cat <<EOFL > $HOOKNAME
sed -i.bak -e '/^\\$NFSDIR/d' /etc/exports
sed -i.bak -e "s/^#rpcbind/rpcbind/" /etc/hosts.deny
echo "OPTIONS=\"-l -h 127.0.0.1\"" > /etc/default/rpcbind
rm -f $HOOKNAME
exit 0
EOFL
    else
	cat <<EOFB > $HOOKNAME
sed -i.bak -e '/^\\$NFSDIR/d' /etc/exports
# stopping services when making a snapshot might not be a
# good idea; i.e., if one of the services hangs
/etc/rc.d/lockd onestop
/etc/rc.d/statd onestop
/etc/rc.d/nfsd onestop
/etc/rc.d/mountd onestop
/etc/rc.d/rpcbind onestop
cp -p /etc/rc.conf.bak /etc/rc.conf
rm -f $HOOKNAME
exit 0
EOFB
    fi
fi
chmod +x $HOOKNAME

echo ""

if [ "$OS" = "Linux" ]; then
    echo "Restarting rpcbind"
    service rpcbind stop
    sleep 1
    service rpcbind start
    sleep 1
fi

echo "Starting NFS services"
if [ "$OS" = "Linux" ]; then
    service nfs-kernel-server start
else
    # nfsd starts rpcbind and mountd
    /etc/rc.d/nfsd onestart
    /etc/rc.d/statd onestart
    /etc/rc.d/lockd onestart
fi

# Give it time to start-up
sleep 5
