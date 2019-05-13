#/usr/bin/make
SRC = $(DESTDIR)/usr/src
SHARE = $(DESTDIR)/usr/share/$(NAME)-dkms

all:

clean:

install:

#tarball, possibly with binaries
ifeq ("$(wildcard $(NAME)-$(VERSION).dkms.tar.gz)", "$(NAME)-$(VERSION).dkms.tar.gz")
	tar zxvf "$(NAME)-$(VERSION).dkms.tar.gz"
	install -d "$(DESTDIR)/lib/modules/$(KVER)/updates/dkms/"
	install -m 644 dkms_main_tree/$(KVER)/$(KARCH)/module/*.ko "$(DESTDIR)/lib/modules/$(KVER)/updates/dkms/"
	rm -rf dkms_main_tree/ dkms_binaries_only/
endif

