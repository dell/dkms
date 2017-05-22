%{?!module_name: %{error: You did not specify a module name (%%module_name)}}
%{?!version: %{error: You did not specify a module version (%%version)}}
Name:		%{module_name}
Version:	%{version}
Release:	1%{?dist}
Summary:	%{module_name}-%{version} RHEL Driver Update Program package

License:	Unknown
Source0:	%{module_name}-%{version}.tar.bz2
BuildRequires:	%kernel_module_package_buildreqs

%kernel_module_package default

%description
%{module_name}-%{version} RHEL Driver Update package.

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
