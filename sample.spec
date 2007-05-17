%define module qla2x00

Summary: Qlogic HBA module
Name: %module_dkms
Version: v6.04.00
Release: 1
Vendor: Qlogic Corporation
Copyright: GPL
Packager: Gary Lerhaupt <gary_lerhaupt@dell.com>
Group: System Environment/Base
BuildArch: noarch
Requires: dkms bash sed
Source0: qla2x00src-%version-emc.tgz
Source1: dkms.conf
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root/

%description
This package contains Qlogic's qla2x00 HBA module meant
for the DKMS framework.

%prep
rm -rf qla2x00src-%version
mkdir qla2x00src-%version
cd qla2x00src-%version
tar xvzf $RPM_SOURCE_DIR/qla2x00src-%version-emc.tgz

%install
if [ "$RPM_BUILD_ROOT" != "/" ]; then
	rm -rf $RPM_BUILD_ROOT
fi
mkdir -p $RPM_BUILD_ROOT/usr/src/%module-%version/
install -m 644 $RPM_SOURCE_DIR/dkms.conf $RPM_BUILD_ROOT/usr/src/%module-%version
install -m 644 qla2x00src-%version/* $RPM_BUILD_ROOT/usr/src/%module-%version

%clean
if [ "$RPM_BUILD_ROOT" != "/" ]; then
	rm -rf $RPM_BUILD_ROOT
fi

%files
%defattr(0644,root,root)
/usr/src/%module-%version/

%pre

%post
/sbin/dkms add -m %module -v %version 
if [ -e /lib/modules/`uname -r`/build/include ]; then
	/sbin/dkms build -m %module -v %version
	/sbin/dkms install -m %module -v %version
else
	echo -e ""
	echo -e "Module build for the currently running kernel was skipped since the"
	echo -e "kernel source for this kernel does not seem to be installed."
fi
exit 0

%preun
echo -e
echo -e "Uninstall of qla2x00 module (version %version) beginning:"
/sbin/dkms remove -m %module -v %version --all
exit 0
