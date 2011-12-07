RELEASE_DATE := "07-December-2011"
RELEASE_MAJOR := 2
RELEASE_MINOR := 2
RELEASE_SUBLEVEL := 0
RELEASE_EXTRALEVEL := .3
RELEASE_NAME := dkms
RELEASE_VERSION := $(RELEASE_MAJOR).$(RELEASE_MINOR).$(RELEASE_SUBLEVEL)$(RELEASE_EXTRALEVEL)
RELEASE_STRING := $(RELEASE_NAME)-$(RELEASE_VERSION)
DIST := unstable
SHELL=bash

SBIN = $(DESTDIR)/usr/sbin
ETC = $(DESTDIR)/etc/dkms
VAR = $(DESTDIR)/var/lib/dkms
MAN = $(DESTDIR)/usr/share/man/man8
INITD = $(DESTDIR)/etc/init.d
INITD_RH = $(DESTDIR)/etc/rc.d/init.d 
LIBDIR = $(DESTDIR)/usr/lib/dkms
BASHDIR = $(DESTDIR)/etc/bash_completion.d
KCONF = $(DESTDIR)/etc/kernel
SHAREDIR = $(DESTDIR)/usr/share
DOCDIR = $(SHAREDIR)/doc/dkms

#Define the top-level build directory
BUILDDIR := $(shell pwd)
TOPDIR := $(shell pwd)

.PHONY = tarball

all: clean tarball rpm debs

clean:
	-rm -rf *~ dist/ dkms-freshmeat.txt

install:
	mkdir -m 0755 -p $(VAR) $(SBIN) $(MAN) $(ETC) $(BASHDIR) $(SHAREDIR) $(LIBDIR)
	sed -e "s/\[INSERT_VERSION_HERE\]/$(RELEASE_VERSION)/" dkms > dkms.versioned
	mv -f dkms.versioned dkms
	install -p -m 0755 dkms_common.postinst $(LIBDIR)/common.postinst
	install -p -m 0755 dkms $(SBIN)
	install -p -m 0755 dkms_autoinstaller $(LIBDIR)
	install -p -m 0644 dkms_framework.conf $(ETC)/framework.conf
	install -p -m 0644 dkms_dbversion $(VAR)
	install -p -m 0644 dkms.bash-completion $(BASHDIR)/dkms
	# install compressed manpage with proper timestamp and permissions
	gzip -c -9 dkms.8 > $(MAN)/dkms.8.gz
	chmod 0644 $(MAN)/dkms.8.gz
	touch --reference=dkms.8 $(MAN)/dkms.8.gz
	mkdir   -p -m 0755 $(KCONF)/prerm.d $(KCONF)/postinst.d
	install -p -m 0755 kernel_prerm.d_dkms  $(KCONF)/prerm.d/dkms
	install -p -m 0755 kernel_postinst.d_dkms $(KCONF)/postinst.d/dkms

DOCFILES=sample.spec sample.conf AUTHORS COPYING README.dkms sample-suse-9-mkkmp.spec sample-suse-10-mkkmp.spec

doc-perms:
	# ensure doc file permissions ok
	chmod 0644 $(DOCFILES)

install-redhat: install doc-perms
	mkdir -m 0755 -p  $(INITD_RH)
	install -p -m 0755 dkms_mkkerneldoth $(LIBDIR)/mkkerneldoth
	install -p -m 0755 dkms_find-provides $(LIBDIR)/find-provides
	install -p -m 0755 lsb_release $(LIBDIR)/lsb_release
	install -p -m 0644 template-dkms-mkrpm.spec $(ETC)
	install -p -m 0644 template-dkms-redhat-kmod.spec $(ETC)
	install -p -m 0755 dkms_autoinstaller $(INITD_RH)

install-doc:
	mkdir -m 0755 -p $(DOCDIR)
	install -p -m 0644 $(DOCFILES) $(DOCDIR)

install-debian: install install-doc
	mkdir   -p -m 0755 $(SHAREDIR)/apport/package-hooks
	install -p -m 0755 dkms_apport.py $(SHAREDIR)/apport/package-hooks/dkms_packages.py
	mkdir   -p -m 0755 $(KCONF)/header_postinst.d
	install -p -m 0755 kernel_postinst.d_dkms $(KCONF)/header_postinst.d/dkms
	mkdir   -p -m 0755 $(ETC)/template-dkms-mkdeb/debian
	ln -s template-dkms-mkdeb $(ETC)/template-dkms-mkdsc
	install -p -m 0664 template-dkms-mkdeb/Makefile $(ETC)/template-dkms-mkdeb/
	install -p -m 0664 template-dkms-mkdeb/debian/* $(ETC)/template-dkms-mkdeb/debian/
	chmod +x $(ETC)/template-dkms-mkdeb/debian/postinst
	chmod +x $(ETC)/template-dkms-mkdeb/debian/prerm
	chmod +x $(ETC)/template-dkms-mkdeb/debian/rules
	rm $(DOCDIR)/COPYING*
	rm $(DOCDIR)/sample*

deb_destdir=$(BUILDDIR)/dist
TARBALL=$(deb_destdir)/$(RELEASE_STRING).tar.gz
tarball: $(TARBALL)

$(TARBALL):
	mkdir -p $(deb_destdir)
	tmp_dir=`mktemp -d --tmpdir dkms.XXXXXXXX` ; \
	cp -a ../$(RELEASE_NAME) $${tmp_dir}/$(RELEASE_STRING) ; \
	sed -e "s/\[INSERT_VERSION_HERE\]/$(RELEASE_VERSION)/" dkms > $${tmp_dir}/$(RELEASE_STRING)/dkms ; \
	sed -e "s/\[INSERT_VERSION_HERE\]/$(RELEASE_VERSION)/" dkms.spec > $${tmp_dir}/$(RELEASE_STRING)/dkms.spec ; \
	find $${tmp_dir}/$(RELEASE_STRING) -depth -name .git -type d -exec rm -rf \{\} \; ; \
	find $${tmp_dir}/$(RELEASE_STRING) -depth -name dist -type d -exec rm -rf \{\} \; ; \
	find $${tmp_dir}/$(RELEASE_STRING) -depth -name \*~ -type f -exec rm -f \{\} \; ; \
	find $${tmp_dir}/$(RELEASE_STRING) -depth -name dkms\*.rpm -type f -exec rm -f \{\} \; ; \
	find $${tmp_dir}/$(RELEASE_STRING) -depth -name dkms\*.tar.gz -type f -exec rm -f \{\} \; ; \
	find $${tmp_dir}/$(RELEASE_STRING) -depth -name dkms-freshmeat.txt -type f -exec rm -f \{\} \; ; \
	rm -rf $${tmp_dir}/$(RELEASE_STRING)/debian ; \
	sync ; sync ; sync ; \
	tar cvzf $(TARBALL) -C $${tmp_dir} $(RELEASE_STRING); \
	rm -rf $${tmp_dir} ;


rpm: $(TARBALL) dkms.spec
	tmp_dir=`mktemp -d --tmpdir dkms.XXXXXXXX` ; \
	mkdir -p $${tmp_dir}/{BUILD,RPMS,SRPMS,SPECS,SOURCES} ; \
	cp $(TARBALL) $${tmp_dir}/SOURCES ; \
	sed "s/\[INSERT_VERSION_HERE\]/$(RELEASE_VERSION)/" dkms.spec > $${tmp_dir}/SPECS/dkms.spec ; \
	pushd $${tmp_dir} > /dev/null 2>&1; \
	rpmbuild -ba --define "_topdir $${tmp_dir}" SPECS/dkms.spec ; \
	popd > /dev/null 2>&1; \
	cp $${tmp_dir}/RPMS/noarch/* $${tmp_dir}/SRPMS/* dist ; \
	rm -rf $${tmp_dir}

debmagic: $(TARBALL)
	mkdir -p dist/
	ln -s $(TARBALL) $(DEB_TMP_BUILDDIR)/$(RELEASE_NAME)_$(RELEASE_VERSION).orig.tar.gz
	tar -C $(DEB_TMP_BUILDDIR) -xzf $(TARBALL)
	cp -ar debian $(DEB_TMP_BUILDDIR)/$(RELEASE_STRING)/debian
	chmod +x $(DEB_TMP_BUILDDIR)/$(RELEASE_STRING)/debian/rules
	cd $(DEB_TMP_BUILDDIR)/$(RELEASE_STRING) ; \
	dch -v $(RELEASE_VERSION)-0 "New upstream version, $(RELEASE_VERSION)"; \
	dpkg-buildpackage -D -b -rfakeroot ; \
	dpkg-buildpackage -D -S -sa -rfakeroot ; \
	mv ../$(RELEASE_NAME)_* $(TOPDIR)/dist/ ; \
	cd -

debs:
	tmp_dir=`mktemp -d --tmpdir dkms.XXXXXXXX` ; \
	make debmagic DEB_TMP_BUILDDIR=$${tmp_dir} DIST=$(DIST); \
	rm -rf $${tmp_dir}

fm:
	sed -e "s/\[INSERT_VERSION_HERE\]/$(RELEASE_VERSION)/" dkms-freshmeat.txt.in > dkms-freshmeat.txt
