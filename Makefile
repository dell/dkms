RELEASE_DATE := "01 October 2021"
RELEASE_MAJOR := 2
RELEASE_MINOR := 8
RELEASE_MICRO := 7
RELEASE_NAME := dkms
RELEASE_VERSION := $(RELEASE_MAJOR).$(RELEASE_MINOR).$(RELEASE_MICRO)
RELEASE_STRING := $(RELEASE_NAME)-$(RELEASE_VERSION)
DIST := unstable
SHELL=bash

SBIN = $(DESTDIR)/usr/sbin
ETC = $(DESTDIR)/etc/dkms
VAR = $(DESTDIR)/var/lib/dkms
MAN = $(DESTDIR)/usr/share/man/man8
INITD = $(DESTDIR)/etc/rc.d/init.d
LIBDIR = $(DESTDIR)/usr/lib/dkms
BASHDIR = $(DESTDIR)/usr/share/bash-completion/completions
KCONF = $(DESTDIR)/etc/kernel
SHAREDIR = $(DESTDIR)/usr/share
DOCDIR = $(SHAREDIR)/doc/dkms
SYSTEMD = $(DESTDIR)/usr/lib/systemd/system

#Define the top-level build directory
BUILDDIR := $(shell pwd)
TOPDIR := $(shell pwd)

.PHONY = tarball

all: clean tarball

clean:
	-rm -rf *~ dist/

install:
	mkdir -p -m 0755 $(VAR) $(SBIN) $(MAN) $(ETC) $(BASHDIR) $(SHAREDIR) $(LIBDIR)
	mkdir -p -m 0755 $(KCONF)/install.d $(KCONF)/prerm.d $(KCONF)/postinst.d
	install -p -m 0755 dkms_common.postinst $(LIBDIR)/common.postinst
	install -p -m 0755 dkms $(SBIN)
	install -p -m 0755 dkms_autoinstaller $(LIBDIR)
	install -p -m 0644 dkms_framework.conf $(ETC)/framework.conf
	install -p -m 0755 sign_helper.sh $(ETC)
	install -p -m 0644 dkms.bash-completion $(BASHDIR)/dkms
	install -p -m 0644 dkms.8 $(MAN)/dkms.8
	install -p -m 0755 kernel_install.d_dkms $(KCONF)/install.d/dkms
	install -p -m 0755 kernel_postinst.d_dkms $(KCONF)/postinst.d/dkms
	install -p -m 0755 kernel_prerm.d_dkms $(KCONF)/prerm.d/dkms
	sed -i -e 's/#RELEASE_STRING#/$(RELEASE_STRING)/' -e 's/#RELEASE_DATE#/$(RELEASE_DATE)/' $(SBIN)/dkms $(MAN)/dkms.8
	gzip -9 $(MAN)/dkms.8

DOCFILES=sample.spec sample.conf COPYING README.md sample-suse-9-mkkmp.spec sample-suse-10-mkkmp.spec

doc-perms:
	# ensure doc file permissions ok
	chmod 0644 $(DOCFILES)

install-redhat-systemd: install doc-perms
	mkdir -m 0755 -p  $(SYSTEMD)
	install -p -m 0755 dkms_mkkerneldoth $(LIBDIR)/mkkerneldoth
	install -p -m 0755 dkms_find-provides $(LIBDIR)/find-provides
	install -p -m 0755 lsb_release $(LIBDIR)/lsb_release
	install -p -m 0644 template-dkms-mkrpm.spec $(ETC)
	install -p -m 0644 template-dkms-redhat-kmod.spec $(ETC)
	install -p -m 0644 dkms.service $(SYSTEMD)

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
	mkdir   -p -m 0755 $(ETC)/template-dkms-mkbmdeb/debian
	install -p -m 0664 template-dkms-mkbmdeb/Makefile $(ETC)/template-dkms-mkbmdeb/
	install -p -m 0664 template-dkms-mkbmdeb/debian/* $(ETC)/template-dkms-mkbmdeb/debian/
	chmod +x $(ETC)/template-dkms-mkbmdeb/debian/rules
	rm $(DOCDIR)/COPYING*
	rm $(DOCDIR)/sample*

TARBALL=$(BUILDDIR)/dist/$(RELEASE_STRING).tar.gz
tarball: $(TARBALL)

$(TARBALL):
	mkdir -p $(BUILDDIR)/dist
	tmp_dir=`mktemp -d --tmpdir dkms.XXXXXXXX` ; \
	cp -a ../$(RELEASE_NAME) $${tmp_dir}/$(RELEASE_STRING) ; \
	sed -e "s/#RELEASE_VERSION#/$(RELEASE_VERSION)/" dkms > $${tmp_dir}/$(RELEASE_STRING)/dkms ; \
	find $${tmp_dir}/$(RELEASE_STRING) -depth -name .git -type d -exec rm -rf \{\} \; ; \
	find $${tmp_dir}/$(RELEASE_STRING) -depth -name dist -type d -exec rm -rf \{\} \; ; \
	find $${tmp_dir}/$(RELEASE_STRING) -depth -name \*~ -type f -exec rm -f \{\} \; ; \
	find $${tmp_dir}/$(RELEASE_STRING) -depth -name dkms\*.rpm -type f -exec rm -f \{\} \; ; \
	find $${tmp_dir}/$(RELEASE_STRING) -depth -name dkms\*.tar.gz -type f -exec rm -f \{\} \; ; \
	rm -rf $${tmp_dir}/$(RELEASE_STRING)/debian ; \
	sync ; sync ; sync ; \
	tar cvzf $(TARBALL) -C $${tmp_dir} $(RELEASE_STRING); \
	rm -rf $${tmp_dir} ;
