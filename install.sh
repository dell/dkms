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
cp -f $DIR/dkms /sbin
cp -f $DIR/dkms.8.gz /usr/share/man/man8
cp -f $DIR/dkms_dbversion /var/dkms/
cp -f $DIR/dkms_autoinstaller /etc/rc.d/init.d/
chkconfig dkms_autoinstaller on
if ! [ -e /etc/dkms_framework.conf ]; then
	cp -f $DIR/dkms_framework.conf /etc/dkms_framework.conf
fi
mkdir -p /var/dkms
chmod 755 /sbin/dkms

