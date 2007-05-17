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

# Upgrade DKMS tree to have arch support
$DIR/dkms_upgrade_add_arch_support.sh

echo "Installing DKMS"
mkdir -p /var/lib/dkms
mkdir -p /etc/dkms
cp -f $DIR/dkms /usr/sbin
gzip -c -9 dkms.8 > /usr/share/man/man8/dkms.8.gz
cp -f $DIR/dkms_dbversion /var/lib/dkms
cp -f $DIR/dkms_autoinstaller /etc/init.d
cp -f $DIR/dkms_mkkerneldoth /usr/sbin
chkconfig dkms_autoinstaller on
if ! [ -e /etc/dkms/framework.conf ]; then
	cp -f $DIR/dkms_framework.conf /etc/dkms/framework.conf
fi
if ! [ -e /etc/dkms/template-dkms-mkrpm.spec ]; then
	cp -f $DIR/template-dkms-mkrpm.spec /etc/dkms
fi
chmod 755 /usr/sbin/dkms
chmod 755 /usr/sbin/dkms_mkkerneldoth
[ -e /sbin/dkms ] && mv /sbin/dkms /sbin/dkms.old 2>/dev/null
