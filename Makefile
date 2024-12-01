RELEASE_DATE := "1 December 2024"
RELEASE_MAJOR := 3
RELEASE_MINOR := 1
RELEASE_MICRO := 3
RELEASE_NAME := dkms
RELEASE_VERSION := $(RELEASE_MAJOR).$(RELEASE_MINOR).$(RELEASE_MICRO)
RELEASE_STRING := $(RELEASE_NAME)-$(RELEASE_VERSION)
SHELL=bash

SBIN = /usr/sbin
LIBDIR = /usr/lib/dkms
MODDIR = /lib/modules
KCONF = /etc/kernel
KINSTALL = /usr/lib/kernel/install.d
SYSTEMD = /usr/lib/systemd/system

#Define the top-level build directory
BUILDDIR := $(shell pwd)

SED			?= sed
SED_SUBSTITUTIONS	 = \
	-e 's,@RELEASE_STRING@,$(RELEASE_STRING),g' \
	-e 's,@RELEASE_DATE@,$(RELEASE_DATE),g' \
	-e 's,@SBINDIR@,$(SBIN),g' \
	-e 's,@KCONFDIR@,$(KCONF),g' \
	-e 's,@MODDIR@,$(MODDIR),g' \
	-e 's,@LIBDIR@,$(LIBDIR),g'

%: %.in
	$(SED) $(SED_SUBSTITUTIONS) $< > $@

all: \
	dkms \
	dkms.8 \
	dkms_autoinstaller \
	dkms.bash-completion \
	dkms.zsh-completion \
	dkms_common.postinst \
	dkms_framework.conf \
	dkms.service \
	debian_kernel_install.d \
	debian_kernel_postinst.d \
	debian_kernel_prerm.d \
	redhat_kernel_install.d

clean:
	-rm -rf dist/
	-rm -f dkms
	-rm -f dkms.8
	-rm -f dkms_autoinstaller
	-rm -f dkms.bash-completion
	-rm -f dkms.zsh-completion
	-rm -f dkms_common.postinst
	-rm -f dkms_framework.conf
	-rm -f dkms.service
	-rm -f debian_kernel_install.d
	-rm -f debian_kernel_postinst.d
	-rm -f debian_kernel_prerm.d
	-rm -f redhat_kernel_install.d

install: all
	$(if $(strip $(VAR)),$(error Setting VAR is not supported))
	install -d -m 0755 $(DESTDIR)/var/lib/dkms
ifneq (,$(DESTDIR))
	$(if $(filter $(DESTDIR)%,$(SBIN)),$(error Using a DESTDIR as prefix for SBIN is no longer supported))
	$(if $(filter $(DESTDIR)%,$(LIBDIR)),$(error Using a DESTDIR as prefix for LIBDIR is no longer supported))
	$(if $(filter $(DESTDIR)%,$(KCONF)),$(error Using a DESTDIR as prefix for KCONF is no longer supported))
endif
	install -D -m 0755 dkms $(DESTDIR)$(SBIN)/dkms
	$(if $(strip $(ETC)),$(error Setting ETC is not supported))
	install -D -m 0644 dkms_framework.conf $(DESTDIR)/etc/dkms/framework.conf
	install -d -m 0755 $(DESTDIR)/etc/dkms/framework.conf.d
	$(if $(strip $(BASHDIR)),$(error Setting BASHDIR is not supported))
	install -D -m 0644 dkms.bash-completion $(DESTDIR)/usr/share/bash-completion/completions/dkms
	install -D -m 0644 dkms.zsh-completion $(DESTDIR)/usr/share/zsh/site-functions/_dkms
	install -D -m 0644 dkms.8 $(DESTDIR)/usr/share/man/man8/dkms.8

install-redhat: install
ifneq (,$(DESTDIR))
	$(if $(filter $(DESTDIR)%,$(SYSTEMD)),$(error Using a DESTDIR as prefix for SYSTEMD is no longer supported))
endif
	install -D -m 0644 dkms.service $(DESTDIR)$(SYSTEMD)/dkms.service
	install -D -m 0755 redhat_kernel_install.d $(DESTDIR)$(KINSTALL)/40-dkms.install

install-debian: install
	$(if $(strip $(SHAREDIR)),$(error Setting SHAREDIR is not supported))
	install -D -m 0755 dkms_autoinstaller $(DESTDIR)$(LIBDIR)/dkms_autoinstaller
	install -D -m 0755 dkms_apport.py $(DESTDIR)/usr/share/apport/package-hooks/dkms_packages.py
	install -D -m 0755 dkms_common.postinst $(DESTDIR)$(LIBDIR)/common.postinst
	install -D -m 0755 debian_kernel_install.d $(DESTDIR)$(KINSTALL)/40-dkms.install
	install -D -m 0755 debian_kernel_postinst.d $(DESTDIR)$(KCONF)/postinst.d/dkms
	install -D -m 0755 debian_kernel_postinst.d $(DESTDIR)$(KCONF)/header_postinst.d/dkms
	install -D -m 0755 debian_kernel_prerm.d $(DESTDIR)$(KCONF)/prerm.d/dkms

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
