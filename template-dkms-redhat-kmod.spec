%{?!module_name: %{error: You did not specify a module name (%%module_name)}}
%{?!version: %{error: You did not specify a module version (%%version)}}
Name:		%{module_name}
Version:	%{version}
Release:	1%{?dist}
Summary:	%{module_name}-%{version} RHEL6 Driver Update Program package

Group:		System/Kernel
License:	Unkown
Source0:	%{module_name}-%{version}.tar.bz2
BuildRoot:	%(mktemp -ud %{_tmppath}/%{module_name}-%{version}-%{release}-XXXXXX)
BuildRequires:	%kernel_module_package_buildreqs

%kernel_module_package default

%description
%{module_name}-%{version} RHEL6 Driver Update package.

%prep
%setup
set -- *
mkdir source
mv "$@" source/
mkdir obj

%build
for flavor in %flavors_to_build; do
	rm -rf obj/$flavor
	cp -r source obj/$flavor
	make -C %{kernel_source $flavor} M=$PWD/obj/$flavor
done

%install
export INSTALL_MOD_PATH=$RPM_BUILD_ROOT
export INSTALL_MOD_DIR=extra/%{name}
for flavor in %flavors_to_build ; do
	make -C %{kernel_source $flavor} modules_install \
		M=$PWD/obj/$flavor
done

%clean
rm -rf $RPM_BUILD_ROOT

%changelog
* Sun Jun 15 2010 Prudhvi Tella <prudhvi_tella@dell.com>
- DKMS template for RHEL6 Driver Update package.
* Sun Mar 28 2010 Jon Masters <jcm@redhat.com>
- Example RHEL6 Driver Update package.
