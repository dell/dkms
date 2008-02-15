RELEASE_DATE := "15-Feb-2008"
RELEASE_MAJOR := 2
RELEASE_MINOR := 0
RELEASE_SUBLEVEL := 17
RELEASE_EXTRALEVEL := .6
RELEASE_NAME := dkms
RELEASE_VERSION := $(RELEASE_MAJOR).$(RELEASE_MINOR).$(RELEASE_SUBLEVEL)$(RELEASE_EXTRALEVEL)
RELEASE_STRING := $(RELEASE_NAME)-$(RELEASE_VERSION)

SBIN = $(DESTDIR)/usr/sbin
ETC = $(DESTDIR)/etc/dkms
VAR = $(DESTDIR)/var/lib/dkms
MAN = $(DESTDIR)/usr/share/man/man8
INITD = $(DESTDIR)/etc/init.d
LIBDIR = $(DESTDIR)/usr/lib/dkms
BASHDIR = $(DESTDIR)/etc/bash_completion.d
DOCDIR = $(DESTDIR)/usr/share/doc/dkms
KCONF = $(DESTDIR)/etc/kernel

#Define the top-level build directory
BUILDDIR := $(shell pwd)
TOPDIR := $(shell pwd)

.PHONY = tarball

all:

clean:
	-rm -f dkms-*.tar.gz dkms-*.src.rpm dkms-*.noarch.rpm *~ dist/

clean-dpkg: clean
	rm -f debian/dkms_autoinstaller.init

copy-init:
	install -m 755 dkms_autoinstaller debian/dkms_autoinstaller.init

install:
	mkdir -m 0755 -p $(VAR) $(SBIN) $(MAN) $(INITD) $(ETC) $(BASHDIR)
	sed -e "s/\[INSERT_VERSION_HERE\]/$(RELEASE_VERSION)/" dkms > dkms.versioned
	mv -f dkms.versioned dkms
	install -p -m 0755 dkms $(SBIN)
	install -p -m 0755 dkms_autoinstaller $(INITD)
	install -p -m 0644 dkms_framework.conf $(ETC)/framework.conf
	install -p -m 0644 dkms_dbversion $(VAR)
	install -p -m 0644 dkms.bash-completion $(BASHDIR)/dkms
	# install compressed manpage with proper timestamp and permissions
	gzip -c -9 dkms.8 > $(MAN)/dkms.8.gz
	chmod 0644 $(MAN)/dkms.8.gz
	touch --reference=dkms.8 $(MAN)/dkms.8.gz


DOCFILES=sample.spec sample.conf AUTHORS COPYING README.dkms sample-suse-9-mkkmp.spec sample-suse-10-mkkmp.spec

doc-perms:
	# ensure doc file permissions ok
	chmod 0644 $(DOCFILES)

install-redhat: install doc-perms
	mkdir   -p -m 0755 $(LIBDIR)
	install -p -m 0755 dkms_mkkerneldoth $(LIBDIR)/mkkerneldoth
	install -p -m 0755 dkms_find-provides $(LIBDIR)/find-provides
	install -p -m 0644 template-dkms-mkrpm.spec $(ETC)

install-doc:
	mkdir -m 0755 -p $(DOCDIR)
	install -p -m 0644 $(DOCFILES) $(DOCDIR)

install-ubuntu: install copy-init install-doc
	mkdir   -p -m 0755 $(KCONF)/prerm.d $(KCONF)/postinst.d $(KCONF)/header_postinst.d
	install -p -m 0755 debian/kernel_prerm.d_dkms  $(KCONF)/prerm.d/dkms
	install -p -m 0755 debian/kernel_postinst.d_dkms $(KCONF)/postinst.d/dkms
	install -p -m 0755 debian/kernel_postinst.d_dkms $(KCONF)/header_postinst.d/dkms
	mkdir   -p -m 0755 $(ETC)/template-dkms-mkdeb/debian
	install -p -m 0664 template-dkms-mkdeb/Makefile $(ETC)/template-dkms-mkdeb/
	install -p -m 0664 template-dkms-mkdeb/debian/* $(ETC)/template-dkms-mkdeb/debian/
	rm $(DOCDIR)/COPYING*

deb_destdir=$(BUILDDIR)/dist
TARBALL=$(deb_destdir)/$(RELEASE_STRING).tar.gz
tarball: $(TARBALL)

$(TARBALL):
	mkdir -p $(deb_destdir)
	tmp_dir=`mktemp -d /tmp/dkms.XXXXXXXX` ; \
	cp -a ../$(RELEASE_NAME) $${tmp_dir}/$(RELEASE_STRING) ; \
	sed -e "s/\[INSERT_VERSION_HERE\]/$(RELEASE_VERSION)/" dkms > $${tmp_dir}/$(RELEASE_STRING)/dkms ; \
	sed -e "s/\[INSERT_VERSION_HERE\]/$(RELEASE_VERSION)/" dkms.spec > $${tmp_dir}/$(RELEASE_STRING)/dkms.spec ; \
	find $${tmp_dir}/$(RELEASE_STRING) -depth -name .git -type d -exec rm -rf \{\} \; ; \
	find $${tmp_dir}/$(RELEASE_STRING) -depth -name dist -type d -exec rm -rf \{\} \; ; \
	find $${tmp_dir}/$(RELEASE_STRING) -depth -name \*~ -type f -exec rm -f \{\} \; ; \
	find $${tmp_dir}/$(RELEASE_STRING) -depth -name dkms\*.rpm -type f -exec rm -f \{\} \; ; \
	find $${tmp_dir}/$(RELEASE_STRING) -depth -name dkms\*.tar.gz -type f -exec rm -f \{\} \; ; \
	sync ; sync ; sync ; \
	tar cvzf $(TARBALL) -C $${tmp_dir} $(RELEASE_STRING) ; \
	rm -rf $${tmp_dir} ;


rpm: $(TARBALL) dkms.spec
	tmp_dir=`mktemp -d /tmp/dkms.XXXXXXXX` ; \
	mkdir -p $${tmp_dir}/{BUILD,RPMS,SRPMS,SPECS,SOURCES} ; \
	cp $(TARBALL) $${tmp_dir}/SOURCES ; \
	sed "s/\[INSERT_VERSION_HERE\]/$(RELEASE_VERSION)/" dkms.spec > $${tmp_dir}/SPECS/dkms.spec ; \
	pushd $${tmp_dir} > /dev/null 2>&1; \
	rpmbuild -ba --define "_topdir $${tmp_dir}" SPECS/dkms.spec ; \
	popd > /dev/null 2>&1; \
	cp $${tmp_dir}/RPMS/noarch/* $${tmp_dir}/SRPMS/* . ; \
	rm -rf $${tmp_dir}

# This is required to ensure DIST is set when necessary
NEEDS_DIST = 0
ifeq ($(MAKECMDGOALS),deb)
  NEEDS_DIST = 1
endif
ifeq ($(MAKECMDGOALS),sdeb)
  NEEDS_DIST = 1
endif

ifeq ($(NEEDS_DIST), 1)
  ifndef DIST
  $(error "Must set DIST={gutsy,hardy,sid,...} for deb and sdeb targets")
  endif
endif


debmagic: $(TARBALL)
	[ -n "$$DEB_TMP_BUILDDIR" ] || (echo "Must set DEB_TMP_BUILDDIR=/tmp/... for deb and sdeb targets"; exit 1)
	[ -n "$$DIST" ] || (echo "Must set DIST={gutsy,hardy,sid,...} for deb and sdeb targets"; exit 1)
	[ -n "$$DIST" ] || echo "Remember to set DISTTAG='~gutsy1' for deb and sdeb targets for backports"
	mkdir -p dist/$(DIST)
	cp $(TARBALL) $(DEB_TMP_BUILDDIR)/$(RELEASE_NAME)_$(RELEASE_VERSION).orig.tar.gz
	tar -C $(DEB_TMP_BUILDDIR) -xzf $(TARBALL)
	cp -ar pkg/debian $(DEB_TMP_BUILDDIR)/$(RELEASE_STRING)/debian
	chmod +x $(DEB_TMP_BUILDDIR)/$(RELEASE_STRING)/debian/rules
	sed -e "s/#DISTTAG#/$(DISTTAG)/g" -e "s/#DIST#/$(DIST)/g" $(DEB_TMP_BUILDDIR)/$(RELEASE_STRING)/debian/changelog.in > $(DEB_TMP_BUILDDIR)/$(RELEASE_STRING)/debian/changelog 
	rm $(DEB_TMP_BUILDDIR)/$(RELEASE_STRING)/debian/changelog.in 
	cd $(DEB_TMP_BUILDDIR)/$(RELEASE_STRING) ; \
	pdebuild --use-pdebuild-internal --buildresult $(TOPDIR)/dist/$(DIST) ; \
	dpkg-buildpackage -D -S -sa -rfakeroot ; \
	mv ../$(RELEASE_NAME)_* $(TOPDIR)/dist/$(DIST) ; \
	cd -

debs:
	tmp_dir=`mktemp -d /tmp/firmware-tools.XXXXXXXX` ; \
	make debmagic DEB_TMP_BUILDDIR=$${tmp_dir} DIST=$(DIST) DISTTAG=$(DISTTAG) ; \
	rm -rf $${tmp_dir}
