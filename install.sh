#!/bin/bash
#
# This script installs devlabel
# devlabel by Gary Lerhaupt

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
mkdir -p /var/dkms
chmod 755 /sbin/dkms

