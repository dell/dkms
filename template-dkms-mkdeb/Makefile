#/usr/bin/make
SRC = $(DESTDIR)/usr/src
POST = $(DESTDIR)/usr/share/$(NAME)-dkms

all:

clean:

postinst:
ifeq ("$(wildcard common.postinst)", "common.postinst")
	install -d "$(POST)"
	install -m 755 $(PREFIX)/usr/lib/dkms/common.postinst $(POST)/postinst
endif

install: postinst
	install -d "$(SRC)"
	install -m 644 $(NAME)-$(VERSION).dkms.tar.gz "$(SRC)"
