#neededforbuild kernel-source kernel-syms

# Change either of these definitions to define flavor. If flavor is
# non-nil, this defines a single-flavor driver package, otherwise
# this driver package will be multi-flavor. (Note that commenting out
# one of these definitions will not work due to some very strange
# RPM behavior!)
%define flavor %{nil}
%define XXflavor default

%define driver_version 1.1
%define kver %(rpm -q --qf '%{VERSION}-%{RELEASE}' kernel-source)
%define arch %(echo %_target_cpu | sed -e 's/i.86/i386/')

Name:         novell-kmp
License:      GPL
Group:        System/Kernel
Autoreqprov:  on
Summary:      An example module package
%if "%flavor" == ""
Version:      %(echo %driver_version-%kver | tr - _)
Requires:     kernel = %kver
%else
Version:      %(echo %driver_version-%kver-%flavor | tr - _)
Requires:     kernel-%flavor = %kver
%endif
Release:      0
Source0:      novell-kmp-%driver_version.tar.bz2
Source1:      depmod.sh
Source2:      mkinitrd.sh
BuildRoot:    %{_tmppath}/%{name}-%{version}-build

%description
Driver test

%prep
# Make sure to include a %setup statement in the %prep section:
# without, the ``%post -f ...'' and ``%postun -f ...'' statements
# will silently fail and produce empty scripts.
%setup -n novell-kmp-%driver_version
mkdir source
mv * source/ || :
mkdir obj

%build
export EXTRA_CFLAGS='-DVERSION=\"%driver_version\"'
%if "%flavor" == ""
flavors=$(ls /usr/src/linux-obj/%arch)
%else
flavors=%flavor
%endif
for flavor in $flavors; do
    if [ $flavor = um ]; then
	# User Mode Linux is an exception for many external kernel modules;
	# we may choose to skip it here.
	continue
    fi
    rm -rf obj-$flavor
    cp -r source obj/$flavor
    make -C /usr/src/linux-obj/%arch/$flavor modules M=$PWD/obj/$flavor
done

%install
export INSTALL_MOD_PATH=$RPM_BUILD_ROOT
export INSTALL_MOD_DIR=updates
for flavor in $(ls obj/); do
    make -C /usr/src/linux-obj/%arch/$flavor modules_install \
	M=$PWD/obj/$flavor
done

set -- $(ls $RPM_BUILD_ROOT/lib/modules)
KERNELRELEASES=$*

set -- $(find $RPM_BUILD_ROOT/lib/modules -type f -name '*.ko' \
	 | sed -e 's:.*/::' -e 's:\.ko$::' | sort -u)
MODULES=$*

(   cat <<-EOF
	# IMPORTANT: Do not change the KERNELRELEASES definition; it will be
	# replaced during driver reuse!
	KERNELRELEASES="$KERNELRELEASES"
	MODULES="$MODULES"
	EOF
    cat %_sourcedir/depmod.sh
    cat %_sourcedir/mkinitrd.sh
) > post_postun.sh

mkdir -p $RPM_BUILD_ROOT/var/lib/YaST2/download
# Insert your download location here:
echo "ftp://ftp.suse.com/pub/suse;SUSE/Novell" \
    > $RPM_BUILD_ROOT/var/lib/YaST2/download/%name

%post -f post_postun.sh

%postun -f post_postun.sh

%files
%defattr(-, root, root)
/lib/modules/*
%dir /var/lib/YaST2
%dir /var/lib/YaST2/download
%config(noreplace) /var/lib/YaST2/download/%name

%changelog
* Thu Dec 01 2005 - agruen@suse.de
- Initial package.
