#!/bin/bash

# This script upgrades DKMS version <1.90 to the new DKMS structure which
# accounts for system architecture.
#
# Along with using this script to update your DKMS tree, you must also
# update to a version of DKMS >=1.90.
#
# DKMS v2.0 will be the first stable release to have arch support.

# bail if no dkms
dkms_version=$(dkms -V 2>/dev/null) || exit
dkms_version=(${dkms_version//./ })

# do nothing if we are already new enough
((${dkms_version[2]} > 1 || \
    (${dkms_version[2]} == 1 && ${dkms_version[3]} >= 90) )) && exit

mv /var/dkms /var/lib/dkms
arch_used=""
[ `uname -m` == "x86_64" ] && [ `cat /proc/cpuinfo | grep -c "Intel"` -gt 0 ] && [ `ls /lib/modules/$kernel_test/build/configs 2>/dev/null | grep -c "ia32e"` -gt 0 ] && arch_used="ia32e" || arch_used=`uname -m`
echo ""
echo "ALERT! ALERT! ALERT!"
echo ""
echo "You are using a version of DKMS which does not support multiple system"
echo "architectures.  Your DKMS tree will now be modified to add this support."
echo ""
echo "The upgrade will assume all built modules are for arch: $arch_used"

# Set important variables
current_kernel=`uname -r`
dkms_tree="/var/lib/dkms"
source_tree="/usr/src"
tmp_location="/tmp"
dkms_frameworkconf="/etc/dkms_framework.conf"

# Source in /etc/dkms_framework.conf
. $dkms_frameworkconf 2>/dev/null

# Add the arch dirs
echo ""
echo "Fixing directories."
for directory in `find $dkms_tree -type d -name "module" -mindepth 3 -maxdepth 4`; do
    dir_to_fix=`echo $directory | sed 's#/module$##'`
    echo "Creating $dir_to_fix/$arch_used..."
    mkdir $dir_to_fix/$arch_used
    mv -f $dir_to_fix/* $dir_to_fix/$arch_used 2>/dev/null
done

# Fix symlinks
echo ""
echo "Fixing symlinks."
for symlink in `find $dkms_tree -type l -name "kernel*" -mindepth 2 -maxdepth 2`; do
    symlink_kernelname=`echo $symlink | sed 's#.*/kernel-##'`
    dir_of_symlink=`echo $symlink | sed 's#/kernel-.*$##'`
    cd $dir_of_symlink
    if [ $(readlink -e "$symlink" | sed 's#/# #g' | wc -w | awk {'print $1'}) -lt 3 ]; then
	echo "Updating $symlink..."
	ln -sf $read_link/$arch_used kernel-$symlink_kernelname-$arch_used
	rm -f $symlink
    fi
    cd -
done
echo ""