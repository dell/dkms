BIN = $(DESTDIR)/usr/sbin
ETC = $(DESTDIR)/etc/dkms
VAR = $(DESTDIR)/var/lib/dkms
MAN = $(DESTDIR)/usr/share/man/man8
INITD = $(DESTDIR)/etc/init.d

all:

clean:


install:
	install -d $(BIN) $(ETC) $(VAR) $(MAN) $(INITD)
	install -m 755 dkms $(BIN)
	gunzip dkms.8.gz
	gzip -9 dkms.8
	install -m 644 dkms.8.gz $(MAN)
	install -m 644 dkms_dbversion $(VAR)
	install -m 644 dkms_framework.conf $(ETC)/framework.conf
	install -m 644 template-dkms-mkrpm.spec $(ETC)
# separately installed by post scripts
#	install -m 755 dkms_autoinstaller $(INITD)

install-redhat: install
	install -m 755 dkms_mkkerneldoth $(BIN)
