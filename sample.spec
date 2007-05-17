%define module megaraid2

Summary: megaraid2 dkms package
Name: %{module}_dkms
Version: 2.00.9
Release: 2
Vendor: LSI
License: GPL
Packager: Gary Lerhaupt <gary_lerhaupt@dell.com>
Group: System Environment/Base
BuildArch: noarch
Requires: dkms > 0.39.10
Requires: bash
Source0: megaraid2.c
Source1: megaraid2.h
Source2: dkms.conf
Source3: Makefile
Source4: AUTHORS
Source5: COPYING
Source6: ChangeLog
Source7: rhel21.patch
Source8: megaraid-2009-hostlock.patch
Source9: post_install.sh
Source10: disk-info
Source11: module-info
Source12: modules.dep
Source13: pcitable
Source14: megaraid2-2.00.9-kernel2.4.9-e.3-all.tgz
Source15: megaraid2-2.00.9-kernel2.4.20-16.9-all.tgz
Source16: megaraid2-2.00.9-kernel2.4.20-9-all.tgz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root/

%description
This package contains LSI's megaraid2 module wrapped for
the DKMS framework.

#%prep
#rm -rf %module-%version
#mkdir %module-%version
#cd %module-%version
#tar xvzf $RPM_SOURCE_DIR/%module-%version.tgz

%install
if [ "$RPM_BUILD_ROOT" != "/" ]; then
	rm -rf $RPM_BUILD_ROOT
fi
mkdir -p $RPM_BUILD_ROOT/usr/src/%module-%version/
mkdir -p $RPM_BUILD_ROOT/usr/src/%module-%version/patches
mkdir -p $RPM_BUILD_ROOT/usr/src/%module-%version/redhat_driver_disk
install -m 644 $RPM_SOURCE_DIR/dkms.conf $RPM_BUILD_ROOT/usr/src/%module-%version
install -m 644 $RPM_SOURCE_DIR/megaraid2.c $RPM_BUILD_ROOT/usr/src/%module-%version
install -m 644 $RPM_SOURCE_DIR/megaraid2.h $RPM_BUILD_ROOT/usr/src/%module-%version
install -m 644 $RPM_SOURCE_DIR/Makefile $RPM_BUILD_ROOT/usr/src/%module-%version
install -m 644 $RPM_SOURCE_DIR/AUTHORS $RPM_BUILD_ROOT/usr/src/%module-%version
install -m 644 $RPM_SOURCE_DIR/COPYING $RPM_BUILD_ROOT/usr/src/%module-%version
install -m 644 $RPM_SOURCE_DIR/ChangeLog $RPM_BUILD_ROOT/usr/src/%module-%version
install -m 755 $RPM_SOURCE_DIR/post_install.sh $RPM_BUILD_ROOT/usr/src/%module-%version
install -m 644 $RPM_SOURCE_DIR/rhel21.patch $RPM_BUILD_ROOT/usr/src/%module-%version/patches
install -m 644 $RPM_SOURCE_DIR/megaraid-2009-hostlock.patch $RPM_BUILD_ROOT/usr/src/%module-%version/patches
install -m 755 $RPM_SOURCE_DIR/disk-info $RPM_BUILD_ROOT/usr/src/%module-%version/redhat_driver_disk
install -m 755 $RPM_SOURCE_DIR/module-info $RPM_BUILD_ROOT/usr/src/%module-%version/redhat_driver_disk
install -m 755 $RPM_SOURCE_DIR/modules.dep $RPM_BUILD_ROOT/usr/src/%module-%version/redhat_driver_disk
install -m 755 $RPM_SOURCE_DIR/pcitable $RPM_BUILD_ROOT/usr/src/%module-%version/redhat_driver_disk
install -m 644 $RPM_SOURCE_DIR/megaraid2-2.00.9-kernel2.4.9-e.3-all.tgz $RPM_BUILD_ROOT/usr/src/%module-%version
install -m 644 $RPM_SOURCE_DIR/megaraid2-2.00.9-kernel2.4.20-9-all.tgz $RPM_BUILD_ROOT/usr/src/%module-%version
install -m 644 $RPM_SOURCE_DIR/megaraid2-2.00.9-kernel2.4.20-16.9-all.tgz $RPM_BUILD_ROOT/usr/src/%module-%version
#install -m 644 %module-%version/* $RPM_BUILD_ROOT/usr/src/%module-%version


%clean
if [ "$RPM_BUILD_ROOT" != "/" ]; then
	rm -rf $RPM_BUILD_ROOT
fi

%files
%defattr(0644,root,root)
/usr/src/%module-%version/

%pre

%post

# Add it (build and install it for currently running kernel if not a BOOT kernel)
/sbin/dkms add -m %module -v %version --rpm_safe_upgrade
if [ `uname -r | grep -c "BOOT"` -eq 0 ] && [ -e /lib/modules/`uname -r`/build/include ]; then
	/sbin/dkms build -m %module -v %version
	/sbin/dkms install -m %module -v %version
elif [ `uname -r | grep -c "BOOT"` -gt 0 ]; then
	echo -e ""
	echo -e "Module build for the currently running kernel was skipped since you"
	echo -e "are running a BOOT variant of the kernel."
else 
	echo -e ""
	echo -e "Module build for the currently running kernel was skipped since the"
	echo -e "kernel source for this kernel does not seem to be installed."
fi

# Load tarballs as necessary
for kernel_name in 2.4.9-e.3; do
	if [ `uname -r | grep -c "$kernel_name"` -gt 0 ]; then
		echo -e ""
		echo -e "Loading/Installing pre-built modules for $kernel_name."
		/sbin/dkms ldtarball --archive=/usr/src/%module-%version/megaraid2-2.00.9-kernel${kernel_name}-all.tgz >/dev/null 
		/sbin/dkms install -m %module -v %version -k ${kernel_name} >/dev/null 2>&1
		/sbin/dkms install -m %module -v %version -k ${kernel_name}smp >/dev/null 2>&1
		/sbin/dkms install -m %module -v %version -k ${kernel_name}enterprise >/dev/null 2>&1
	fi	
done
for kernel_name in 2.4.20-9 2.4.20-16.9; do 
	if [ `uname -r | grep -c "$kernel_name"` -gt 0 ]; then
		echo -e ""
		echo -e "Loading/Installing pre-built modules for $kernel_name."
		/sbin/dkms ldtarball --archive=/usr/src/%module-%version/megaraid2-2.00.9-kernel${kernel_name}-all.tgz >/dev/null 
		/sbin/dkms install -m %module -v %version -k ${kernel_name} >/dev/null 2>&1
		/sbin/dkms install -m %module -v %version -k ${kernel_name}smp >/dev/null 2>&1
		/sbin/dkms install -m %module -v %version -k ${kernel_name}bigmem >/dev/null 2>&1
	fi
done
exit 0


%preun
echo -e
echo -e "Uninstall of megaraid2 module (version %version) beginning:"
/sbin/dkms remove -m %module -v %version --all --rpm_safe_upgrade
exit 0
