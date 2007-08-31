%define module megaraid2
%define version 2.10.1

Summary: megaraid2 dkms package
Name: %{module}
Version: %{version}
Release: 2dkms
Vendor: LSI
License: GPL
Packager: Ganesh Viswanathan <ganesh_viswanathan@dell.com>
Group: System Environment/Base
BuildArch: noarch
Requires: dkms >= 1.00
Requires: bash
# There is no Source# line for dkms.conf since it has been placed
# into the source tarball of SOURCE0
Source0: %{module}-%{version}-src.tar.gz
Source1: %{module}-%{version}-kernel2.4.9-e.3-all.tgz
Source2: %{module}-%{version}-kernel2.4.20-16.9-all.tgz
Source3: %{module}-%{version}-kernel2.4.20-9-all.tgz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root/

%description
This package contains LSI's megaraid2 module wrapped for
the DKMS framework.

%prep
rm -rf %{module}-%{version}
mkdir %{module}-%{version}
cd %{module}-%{version}
tar xvzf $RPM_SOURCE_DIR/%{module}-%{version}-src.tar.gz

%install
if [ "$RPM_BUILD_ROOT" != "/" ]; then
	rm -rf $RPM_BUILD_ROOT
fi
mkdir -p $RPM_BUILD_ROOT/usr/src/%{module}-%{version}/
mkdir -p $RPM_BUILD_ROOT/usr/src/%{module}-%{version}/patches
mkdir -p $RPM_BUILD_ROOT/usr/src/%{module}-%{version}/redhat_driver_disk
cp -rf %{module}-%{version}/* $RPM_BUILD_ROOT/usr/src/%{module}-%{version}
install -m 644 $RPM_SOURCE_DIR/%{module}-%{version}-kernel2.4.9-e.3-all.tgz $RPM_BUILD_ROOT/usr/src/%{module}-%{version}
install -m 644 $RPM_SOURCE_DIR/%{module}-%{version}-kernel2.4.20-9-all.tgz $RPM_BUILD_ROOT/usr/src/%{module}-%{version}
install -m 644 $RPM_SOURCE_DIR/%{module}-%{version}-kernel2.4.20-16.9-all.tgz $RPM_BUILD_ROOT/usr/src/%{module}-%{version}

%clean
if [ "$RPM_BUILD_ROOT" != "/" ]; then
	rm -rf $RPM_BUILD_ROOT
fi

%files
%defattr(-,root,root)
/usr/src/%{module}-%{version}/

%pre

%post
dkms add -m %{module} -v %{version} --rpm_safe_upgrade

# Load tarballs as necessary
loaded_tarballs=""
for kernel_name in 2.4.9-e.3; do
        if [ `uname -r | grep -c "$kernel_name"` -gt 0 ] && [ `uname -m | grep -c "i*86"` -gt 0 ]; then
                echo -e ""
                echo -e "Loading/Installing pre-built modules for $kernel_name."
                dkms ldtarball --archive=/usr/src/%{module}-%{version}/%{module}-%{version}-kernel${kernel_name}-all.tgz >/dev/null
                dkms install -m %{module} -v %{version} -k ${kernel_name} >/dev/null 2>&1
                dkms install -m %{module} -v %{version} -k ${kernel_name}smp >/dev/null 2>&1
                dkms install -m %{module} -v %{version} -k ${kernel_name}enterprise >/dev/null 2>&1
		loaded_tarballs="true"
        fi
done
for kernel_name in 2.4.20-9 2.4.20-16.9; do
        if [ `uname -r | grep -c "$kernel_name"` -gt 0 ] && [ `uname -m | grep -c "i*86"` -gt 0 ]; then
                echo -e ""
                echo -e "Loading/Installing pre-built modules for $kernel_name."
                dkms ldtarball --archive=/usr/src/%{module}-%{version}/%{module}-%{version}-kernel${kernel_name}-all.tgz >/dev/null
                dkms install -m %{module} -v %{version} -k ${kernel_name} >/dev/null 2>&1
                dkms install -m %{module} -v %{version} -k ${kernel_name}smp >/dev/null 2>&1
                dkms install -m %{module} -v %{version} -k ${kernel_name}bigmem >/dev/null 2>&1
		loaded_tarballs="true"
        fi
done

# If we haven't loaded a tarball, then try building it for the current kernel
if [ -z "$loaded_tarballs" ]; then
	if [ `uname -r | grep -c "BOOT"` -eq 0 ] && [ -e /lib/modules/`uname -r`/build/include ]; then
		dkms build -m %{module} -v %{version}
		dkms install -m %{module} -v %{version}
	elif [ `uname -r | grep -c "BOOT"` -gt 0 ]; then
		echo -e ""
		echo -e "Module build for the currently running kernel was skipped since you"
		echo -e "are running a BOOT variant of the kernel."
	else
		echo -e ""
		echo -e "Module build for the currently running kernel was skipped since the"
		echo -e "kernel source for this kernel does not seem to be installed."
	fi
fi
exit 0

%preun
echo -e
echo -e "Uninstall of megaraid2 module (version %{version}) beginning:"
dkms remove -m %{module} -v %{version} --all --rpm_safe_upgrade
exit 0
