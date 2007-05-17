Summary: Dynamic Kernel Module Support Framework
Name: dkms
Version: 0.28.05
Release: 1
Vendor: Dell Computer Corporation
Copyright: GPL
Packager: Gary Lerhaupt <gary_lerhaupt@dell.com>
Group: System Environment/Base
Requires: gcc bash sed gawk findutils tar
Source: dkms-%version.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root/

%description
This package contains the framework for the Dynamic
Kernel Module Support (DKMS) method for installing
module RPMS as originally developed by the Dell
Computer Corporation.

%prep

%setup -q

%install
if [ "$RPM_BUILD_ROOT" != "/" ]; then
        rm -rf $RPM_BUILD_ROOT
fi
mkdir -p $RPM_BUILD_ROOT/{var/dkms,sbin,usr/share/man/man8}
install -m 755 dkms $RPM_BUILD_ROOT/sbin/dkms
install -m 644 dkms.8.gz $RPM_BUILD_ROOT/usr/share/man/man8

%clean 
if [ "$RPM_BUILD_ROOT" != "/" ]; then
        rm -rf $RPM_BUILD_ROOT
fi

%files
%defattr(-,root,root)
%attr(0755,root,root) /sbin/dkms
%attr(0755,root,root) /var/dkms
%doc %attr(0644,root,root) /usr/share/man/man8/dkms.8.gz

%changelog
* Wed May 14 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.28.05-1
- Fixed a typo in the man page.

* Tue May 05 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.28.04-1
- Fixed ldtarball/mktarball to obey source_tree & dkms_tree (Reported By: Jordan Hargrave <jordan_hargrave@dell.com>)
- Added DKMS mailing list to man page

* Tue Apr 29 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.27.05-1
- Changed NEEDED_FOR_BOOT to REMAKE_INITRD as this makes more sense
- Redid handling of modifying modules.conf 
- Added MODULE_CONF_ALIAS_TYPE to specs

* Mon Apr 28 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.26.12-1
- Started adding ldtarball support
- added the --force option
- Update man page

* Thu Apr 24 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.26.05-1
- Started adding mktarball support
- Fixed up the spec file to use the tarball

* Tue Mar 25 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.25.14-1
- Continued integrating mkdriverdisk
- Updated man page

* Mon Mar 24 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.25.03-1
- Added renaming ability to modules after builds (MODULE_NAME="beforename.o:aftername.o")
- Started adding mkdriverdisk support
- Added distro parameter for use with mkdriverdisk
- Now using readlink to determine symlink pointing location
- Added redhat BOOT config to default location of config files
- Fixed a bug in read_conf that caused the wrong make subdirective to be used
- Remove root requirement for build action

* Wed Mar 19 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.23.19-1
- Fixed archiving of original modules (Reported by: Kris Jordan <kris@sagebrushnetworks.com>)

* Wed Mar 12 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.23.18-1
- Added kernel specific patching ability

* Mon Mar 10 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.23.16-1
- Removed the sourcing in of /etc/init.d/functions as it was unused anyway
- Implemented generic patching support
- Updated man page
- Fixed timing of the creation of DKMS built infrastructure in case of failure

* Fri Mar 07 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.23.11-1
- Builds now occur in /var/dkms/$module/$module_version/build and not in /usr/src
- Fixed the logging of the kernel_config

* Thu Mar 06 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.23.01-1
- Started adding patch support
- Redid reading implementation of modules_conf entries in dkms.conf (now supports more than 5)
- Updated man page

* Tue Mar 04 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.22.06-1
- Module names are not just assumed to end in .o any longer (you must specify full module name)
- At exit status to invoke_command when bad exit status is returned

* Fri Feb 28 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.22.03-1
- Changed the way variables are handled in dkms.conf, %kernelver to $kernelver

* Mon Feb 24 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.22.02-1
- Fixed a typo in install

* Tue Feb 11 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.22.01-1
- Fixed bug in remove which made it too greedy
- Updated match code

* Mon Feb 10 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.21.16-1
- Added uninstall action
- Updated man page

* Fri Feb 07 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.20.06-1
- Added --config option to specify where alternate .config location exists
- Updated the man page to indicate the new option.
- Updated the spec to allow for software versioning printout
- Added -V which prints out the current dkms version and exits

* Thu Jan 09 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.19.01-1
- Added GPL stuffs

* Mon Dec 09 2002 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.18.04-1
- Added support for multiple modules within the same install
- Added postadd and fixed up the man page

* Fri Dec 06 2002 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.17.01-1
- Cleaned up the spec file.

* Fri Nov 22 2002 Gary Lerhaupt <gary_lerhaupt@dell.com>
- Fixed a bug in finding MAKE subdirectives

* Thu Nov 21 2002 Gary Lerhaupt <gary_lerhaupt@dell.com>
- Fixed make.log path error when module make fails
- Fixed invoke_command to work under RH8.0
- DKMS now edits kernel makefile to get around RH8.0 problems

* Wed Nov 20 2002 Gary Lerhaupt <gary_lerhaupt@dell.com>
- Reworked the implementation of -q, --quiet

* Tue Nov 19 2002 Gary Lerhaupt <gary_lerhaupt@dell.com>
- Version 0.16: added man page

* Mon Nov 18 2002 Gary Lerhaupt <gary_lerhaupt@dell.com>
- Version 0.13: added match option
- Version 0.14: dkms is no longer a SysV service
- Added depmod after install and remove
- Version 0.15: added MODULES_CONF directives in dkms.conf

* Fri Nov 15 2002 Gary Lerhaupt <gary_lerhaupt@dell.com>
- Version 0.12: added the -q (quiet) option

* Thu Nov 14 2002 Gary Lerhaupt <gary_lerhaupt@dell.com>
- Version 0.11: began coding the status function

* Wed Nov 13 2002 Gary Lerhaupt <gary_lerhaupt@dell.com>
- Changed the name to DKMS
- Moved original_module to its own separate directory structure
- Removal now does a complete clean up

* Mon Nov 11 2002 Gary Lerhaupt <gary_lerhaupt@dell.com>
- Split build into build and install
- dkds.conf is now sourced in
- added kernelver variable to dkds.conf

* Fri Nov 8 2002 Gary Lerhaupt <gary_lerhaupt@dell.com>
- Added date to make.log
- Created the prepare_kernel function

* Thu Nov 7 2002 Gary Lerhaupt <gary_lerhaupt@dell.com>
- Barebones implementation complete

* Wed Oct 30 2002 Gary Lerhaupt <gary_lerhaupt@dell.com>
- Initial coding
