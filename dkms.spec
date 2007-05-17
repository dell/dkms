Summary: Dynamic Kernel Module Support Framework
Name: dkms
Version: 0.38.03
Release: 1
Vendor: Dell Computer Corporation
License: GPL
Packager: Gary Lerhaupt <gary_lerhaupt@dell.com>
Group: System Environment/Base
Requires: gcc bash sed gawk findutils tar cpio gzip grep mktemp
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
mkdir -p $RPM_BUILD_ROOT/{var/dkms,sbin,usr/share/man/man8,etc,etc/rc.d/init.d}
install -m 755 dkms $RPM_BUILD_ROOT/sbin/dkms
install -m 644 dkms.8.gz $RPM_BUILD_ROOT/usr/share/man/man8
install -m 644 dkms_framework.conf  $RPM_BUILD_ROOT/etc/dkms_framework.conf
install -m 644 dkms_dbversion $RPM_BUILD_ROOT/var/dkms/dkms_dbversion
install -m 755 dkms_autoinstaller $RPM_BUILD_ROOT/etc/rc.d/init.d/dkms_autoinstaller

%clean 
if [ "$RPM_BUILD_ROOT" != "/" ]; then
        rm -rf $RPM_BUILD_ROOT
fi

%files
%defattr(-,root,root)
%attr(0755,root,root) /sbin/dkms
%attr(0755,root,root) /var/dkms
%attr(0755,root,root) /etc/rc.d/init.d/dkms_autoinstaller
%doc %attr(0644,root,root) /usr/share/man/man8/dkms.8.gz
%doc %attr(0644,root,root) sample.spec AUTHORS COPYING
%config(noreplace) /etc/dkms_framework.conf

%post
/sbin/chkconfig dkms_autoinstaller on

%changelog
* Thu Sep 25 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.38.03-1
- Fixed tmp_dir_name typo in ldtarball
- Fixed mkdriverdisk to correctly create kernel/module structure
- Don't expect a rhdd-6.1 file for RH driver disk, dkms will create it
- Remove mkdriverdisk warning on non BOOT kernels
- Moved driver_disk directory location to underneath $module_version
- mkdriverdisk can now accept multiple kernel versions
- Updated man page with info about $dkms_tree and $source_tree as dkms.conf variables

* Wed Sep 24 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.37.10-1
- Don't allow installs of modules onto non-existant kernels
- Suppressed stderr on some commands
- Fixed brain-dead bug for REMAKE INITRD
- During uninstall, dont remake initrd if it was not installed
- ldtarball into unique tempdir and delete it when finished

* Tue Sep 23 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.37.04-1
- Changed PATCH to array based system (added PATCH_MATCH array)
- PATCHes can now be matched against regular expressions, not just substrings
- Changed MODULES_CONF to array based system
- CHANGED MAKE to array based system (added MAKE_MATCH array)
- MAKEs can now be matched against regular expressions, not just substrings.
- Updated man page

* Mon Sep 22 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.36.10-1
- Changed autoinstaller bootup priority from 08 to 04
- Changed invoke_command routine to use mktemp for better security
- Changed invoke_command in dkms_autoinstaller too

* Fri Sep 19 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.36.05-1
- Continued bug testing and fixing new features

* Wed Sep 17 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.36.02-1
- Got rid of MODULE_NAME: replaced with BUILT_MODULE_NAME, DEST_MODULE_NAME arrays
- Got rid of LOCATION: replaced with BUILT_MODULE_LOCATION, DEST_MODULE_LOCATION arrays
- Update man page

* Tue Sep 16 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.36.01-1
- Fixed the setting of the gt2dot4 variable

* Wed Sep 10 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.35.02-1
- Added PACKAGE_NAME, PACKAGE_VERSION requirements to dkms.conf for gmodconfig use
- Fixed creation of /var/dkms before cp of dkms_dbversion in install.sh

* Mon Sep 08 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.34.10-1
- Continued adding autoinstall stuff
- Updated man page

* Fri Sep 05 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.34.01-1
- Added dkms_autoinstaller service (builds module on boot if AUTOINSTALL="yes" in dkms.conf)
- DKMS usage no longer sent to std_err
- Added --no-prepare-kernel cli option

* Fri Aug 08 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.33.02-1
- Fixed quote bugs in match (Reported by: John Hull <john_hull@dell.com>) 
- Added Fred Treasure to the AUTHORS list
- Added dkms_dbversion file to DKMS tree to track architecture of dkms db layout

* Thu Jul 03 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.32.04-1
- Added mkinitrd support for SuSE (etc_sysconfig_kernel_modify)
- Added generic make command for kernel >2.4 (make -C <path-to-kernel-source> SUBDIRS=<build dir> modules)
- Fixed kernel prepare to do Red Hat/Generic by default
- Only do make dep if < 2.5

* Tue Jun 03 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.31.04-1
- Modified the Red Hat prep routine to be smaller and more robust (including summit support)
- Added sample.spec to the sources for /usr/share/doc
- If you save a .config before make mrproper, return it right afterwards
- Updated the man page

* Fri May 30 2003 Gary Lerhaupt <gary_lerahupt@dell.com> 0.30.17-1
- Added a remake_initrd function to keep SuSE from doing wrong things
- If you know the correct right steps for rebuilding SuSE initrds, please let me know!
- Updated man page

* Thu May 29 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.30.15-1
- Added a native readlink function to make sure it exists
- Added a mkdir -p to $location to make sure it exists
- Added --directive

* Wed May 28 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.30.05-1
- Added kernel preparation support for SLES/United Linux (Many thanks to: Fred Treasure <fwtreas@us.ibm.com>)

* Tue May 20 2003 Gary Lerhaupt <gary_lerhaupt@dell.com> 0.29.09-1
- On remove, to remove all kernel versions you must now specify --all
- Added grep, cpio and gzip to the Requires of the RPM
- Added cleaning kernel tree (make mrproper) after last build completes
- Before prepare kernel, the current .config is stored in memory to be restored later
- Added a verbose warning to the status command to remind people it only shows DKMS modules
- Added /etc/dkms_framwork.conf for controlling source_tree and dkms_tree
- Added the undocumented --dkmstree and --sourcetree options for cli control of these vars
- When looking for original modules, dkms now employs the find command to expand search past $location
- Updated man page

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
