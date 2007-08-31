%{?!module_name: %{error: You did not specify a module name (%%module_name)}}
%{?!version: %{error: You did not specify a module version (%%version)}}
%{?!kernel_versions: %{error: You did not specify kernel versions (%%kernel_version)}}
%{?!packager: %define packager DKMS <dkms-devel@lists.us.dell.com>}
%{?!license: %define license Unknown}
%{?!_dkmsdir: %define _dkmsdir /var/lib/dkms}
%{?!_srcdir: %define _srcdir %_prefix/src}

Summary:	%{module_name} %{version} dkms package
Name:		%{module_name}
Version:	%{version}
License:	%license
Release:	1dkms
BuildArch:	noarch
Group:		System/Kernel
Requires: 	dkms >= 1.95
BuildRequires: 	dkms
Source0:	%{module_name}-%{version}-mktarball.dkms.tgz
BuildRoot: 	%{_tmppath}/%{name}-%{version}-%{release}-root/

%description
Kernel modules for %{module_name} %{version} in a DKMS wrapper.

%prep
/usr/sbin/dkms mktarball -m %module_name -v %version %mktarball_line --archive `basename %{SOURCE0}`
cp -af %{_dkmsdir}/%{module_name}/%{version}/tarball/`basename %{SOURCE0}` %{SOURCE0}

%install
if [ "$RPM_BUILD_ROOT" != "/" ]; then
        rm -rf $RPM_BUILD_ROOT
fi
mkdir -p $RPM_BUILD_ROOT/%{_srcdir}/%{module_name}-%{version}/
install -m 644 %{SOURCE0} $RPM_BUILD_ROOT/%{_srcdir}/%{module_name}-%{version}

%clean
if [ "$RPM_BUILD_ROOT" != "/" ]; then
        rm -rf $RPM_BUILD_ROOT
fi

%post
# Determine current arch / kernel
[ `uname -m` == "x86_64" ] && [ `cat /proc/cpuinfo | grep -c "Intel"` -gt 0 ] && [ -e /etc/redhat-release ] && [ `grep -c "Taroon" /etc/redhat-release` -gt 0 ] && c_arch="ia32e" || c_arch=`uname -m`
c_kern=`uname -r`

# Load prebuilt binaries
echo -e ""
echo -e "Loading kernel module source and prebuilt module binaries (if any)"
dkms ldtarball --archive %{_srcdir}/%{module_name}-%{version}/%{module_name}-%{version}-mktarball.dkms.tgz >/dev/null 2>&1

# Install prebuilt binaries
echo -e "Installing prebuilt kernel module binaries (if any)"
IFS='
'
for kern in `dkms status -m %{module_name} -v %{version} -a $c_arch | grep ": built" | awk {'print $3'} | sed 's/,$//'`; do
	dkms install -m %{module_name} -v %{version} -k $kern -a $c_arch >/dev/null 2>&1
done
unset IFS

# If nothing installed for `uname -r` build and install it
if [ `dkms status -m %{module_name} -v %{version} -k $c_kern -a $c_arch | grep -c ": installed"` -eq 0 ]; then
	if [ `echo $c_kern | grep -c "BOOT"` -eq 0 ] && [ -e /lib/modules/$c_kern/build/include ]; then
		dkms build -m %{module_name} -v %{version}
		dkms install -m %{module_name} -v %{version}
        elif [ `echo $c_kern | grep -c "BOOT"` -gt 0 ]; then
                echo -e ""
                echo -e "Module build for the currently running kernel was skipped since you"
                echo -e "are running a BOOT variant of the kernel."
        else
                echo -e ""
                echo -e "Module build for the currently running kernel was skipped since the"
                echo -e "kernel source for this kernel does not seem to be installed."
        fi
fi

echo -e ""
echo -e "Your DKMS tree now includes:"
dkms status -m %{module_name} -v %{version}
exit 0

%preun
echo -e
echo -e "Uninstall of %{module_name} module (version %{version}) beginning:"
dkms remove -m %{module_name} -v %{version} --all --rpm_safe_upgrade
exit 0

%files
%defattr(-,root,root)
/usr/src/%{module_name}-%{version}/

%changelog
* %(date "+%a %b %d %Y") %packager %{version}-%{release}
- Automatic build by DKMS

