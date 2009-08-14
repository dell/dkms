#/usr/bin/make
SRC = $(DESTDIR)/usr/src
POST = $(DESTDIR)/usr/share/$(NAME)-dkms

all:

clean:

postinst:

tarball:

install: postinst tarball
	install -d "$(SRC)"
	cp -a $(NAME)-$(VERSION) $(SRC)
	chmod 644 -R "$(SRC)/$(NAME)-$(VERSION)"

#tarball, possibly with binaries
ifeq ("$(wildcard $(NAME)-$(VERSION).dkms.tar.gz)", "$(NAME)-$(VERSION).dkms.tar.gz")
	install -m 644 $(NAME)-$(VERSION).dkms.tar.gz "$(SRC)"
endif

#postinst, only if we are supporting legacy mode
ifeq ("$(wildcard common.postinst)", "common.postinst")
	install -d "$(POST)"
	install -m 755 $(PREFIX)/usr/lib/dkms/common.postinst $(POST)/postinst
endif
