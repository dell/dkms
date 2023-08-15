RELEASE_DATE := "27 April 2023"
RELEASE_MAJOR := 3
RELEASE_MINOR := 0
RELEASE_MICRO := 11
RELEASE_NAME := dkms
RELEASE_VERSION := $(RELEASE_MAJOR).$(RELEASE_MINOR).$(RELEASE_MICRO)
RELEASE_STRING := $(RELEASE_NAME)-$(RELEASE_VERSION)
SHELL=bash

SBIN = /usr/sbin
LIBDIR = $(DESTDIR)/usr/lib/dkms
KCONF = $(DESTDIR)/etc/kernel
SYSTEMD = /usr/lib/systemd/system

#Define the top-level build directory
BUILDDIR := $(shell pwd)

all: dkms dkms.8

clean:
	-rm -rf dist/
	-rm -rf dkms
	-rm -rf dkms.8

dkms: dkms.in
	sed -e 's/#RELEASE_STRING#/$(RELEASE_STRING)/' $^ > $@

dkms.8: dkms.8.in
	sed -e 's/#RELEASE_STRING#/$(RELEASE_STRING)/' -e 's/#RELEASE_DATE#/$(RELEASE_DATE)/' $^ > $@

install: all
	$(if $(strip $(VAR)),$(error Setting VAR is not supported))
	install -d -m 0755 $(DESTDIR)/var/lib/dkms
	install -D -m 0755 dkms_common.postinst $(LIBDIR)/common.postinst
ifneq (,$(DESTDIR))
	$(if $(filter $(DESTDIR)%,$(SBIN)),$(error Using a DESTDIR as prefix for SBIN is no longer supported))
endif
	install -D -m 0755 dkms $(DESTDIR)$(SBIN)/dkms
	install -D -m 0755 dkms_autoinstaller $(LIBDIR)/dkms_autoinstaller
	$(if $(strip $(ETC)),$(error Setting ETC is not supported))
	install -D -m 0644 dkms_framework.conf $(DESTDIR)/etc/dkms/framework.conf
	install -d -m 0755 $(DESTDIR)/etc/dkms/framework.conf.d
	$(if $(strip $(BASHDIR)),$(error Setting BASHDIR is not supported))
	install -D -m 0644 dkms.bash-completion $(DESTDIR)/usr/share/bash-completion/completions/dkms
	install -D -m 0644 dkms.8 $(DESTDIR)/usr/share/man/man8/dkms.8
	install -D -m 0755 kernel_install.d_dkms $(KCONF)/install.d/40-dkms.install
	install -D -m 0755 kernel_postinst.d_dkms $(KCONF)/postinst.d/dkms
	install -D -m 0755 kernel_prerm.d_dkms $(KCONF)/prerm.d/dkms

install-redhat: install
ifneq (,$(DESTDIR))
	$(if $(filter $(DESTDIR)%,$(SYSTEMD)),$(error Using a DESTDIR as prefix for SYSTEMD is no longer supported))
endif
	install -D -m 0644 dkms.service $(DESTDIR)$(SYSTEMD)/dkms.service

install-debian: install
	$(if $(strip $(SHAREDIR)),$(error Setting SHAREDIR is not supported))
	install -D -m 0755 dkms_apport.py $(DESTDIR)/usr/share/apport/package-hooks/dkms_packages.py
	install -D -m 0755 kernel_postinst.d_dkms $(KCONF)/header_postinst.d/dkms

install-doc:
	$(if $(strip $(DOC)),$(error Setting DOCDIR is not supported))
	install -d -m 0755 $(DESTDIR)/usr/share/doc/dkms
	install -m 0644 COPYING README.md $(DESTDIR)/usr/share/doc/dkms

.PHONY = tarball

TARBALL=$(BUILDDIR)/dist/$(RELEASE_STRING).tar.gz
tarball: $(TARBALL)

$(TARBALL): all
	mkdir -p $(@D)
	git archive --prefix=$(RELEASE_STRING)/ --add-file=dkms --add-file=dkms.8 -o $@ HEAD
