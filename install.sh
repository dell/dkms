#!/bin/bash
#
# This script installs DKMS
# DKMS by Gary Lerhaupt

if [ `dirname $0 | grep -c "^/"` -gt 0 ]; then
    DIR=`dirname $0`
else
    DIR=`pwd``dirname $0 | sed 's/^\.//'`
fi


USERID=`id -u`
if [ "$USERID" -ne 0 ]; then 
	echo "Must be root to install."
	exit 1
fi



echo "Installing DKMS"
mkdir -p /var/dkms
cp -f $DIR/dkms /usr/sbin
cp -f $DIR/dkms.8.gz /usr/share/man/man8
cp -f $DIR/dkms_dbversion /var/dkms
cp -f $DIR/dkms_autoinstaller /etc/init.d
cp -f $DIR/dkms_mkkerneldoth /usr/sbin
chkconfig dkms_autoinstaller on
if ! [ -e /etc/dkms_framework.conf ]; then
	cp -f $DIR/dkms_framework.conf /etc/dkms_framework.conf
fi
chmod 755 /usr/sbin/dkms
chmod 755 /usr/sbin/dkms_mkkerneldoth
[ -e /sbin/dkms ] && mv /sbin/dkms /sbin/dkms.old 2>/dev/null
