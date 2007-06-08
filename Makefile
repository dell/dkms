RELEASE_DATE := "08-Jun-2007"
RELEASE_MAJOR := 2
RELEASE_MINOR := 0
RELEASE_SUBLEVEL := 17
RELEASE_EXTRALEVEL :=
RELEASE_NAME := dkms
RELEASE_VERSION := $(RELEASE_MAJOR).$(RELEASE_MINOR).$(RELEASE_SUBLEVEL)$(RELEASE_EXTRALEVEL)
RELEASE_STRING := $(RELEASE_NAME)-$(RELEASE_VERSION)

BIN = $(DESTDIR)/usr/sbin
ETC = $(DESTDIR)/etc/dkms
VAR = $(DESTDIR)/var/lib/dkms
MAN = $(DESTDIR)/usr/share/man/man8
INITD = $(DESTDIR)/etc/init.d

.PHONY = tarball

all:

clean:
	-rm dkms-*.tar.gz dkms-*.src.rpm dkms-*.noarch.rpm *~

install:
	install -d $(BIN) $(ETC) $(VAR) $(MAN) $(INITD)
	install -m 755 dkms $(BIN)
	gzip -c -9 dkms.8 > dkms.8.gz
	install -m 644 dkms.8.gz $(MAN)
	install -m 644 dkms_dbversion $(VAR)
	install -m 644 dkms_framework.conf $(ETC)/framework.conf
	install -m 644 template-dkms-mkrpm.spec $(ETC)
# separately installed by post scripts
#	install -m 755 dkms_autoinstaller $(INITD)

install-redhat: install
	install -m 755 dkms_mkkerneldoth $(BIN)



tarball:
	-rm $(RELEASE_STRING).tar.gz
	tmp_dir=`mktemp -d /tmp/dkms.XXXXXXXX` ; \
	cp -a ../$(RELEASE_NAME) $${tmp_dir}/$(RELEASE_STRING) ; \
	sed "s/\[INSERT_VERSION_HERE\]/$(RELEASE_VERSION)/" dkms > $${tmp_dir}/$(RELEASE_STRING)/dkms ; \
	sed "s/\[INSERT_VERSION_HERE\]/$(RELEASE_VERSION)/" dkms.spec > $${tmp_dir}/$(RELEASE_STRING)/dkms.spec ; \
	find $${tmp_dir}/$(RELEASE_STRING) -depth -name .git -type d -exec rm -rf \{\} \; ; \
	find $${tmp_dir}/$(RELEASE_STRING) -depth -name \*~ -type f -exec rm -f \{\} \; ; \
	sync ;\
	sync ;\
	sync ;\
	pushd $${tmp_dir} > /dev/null 2>&1; \
	tar cvzf $(RELEASE_STRING).tar.gz $(RELEASE_STRING) ; \
	popd > /dev/null 2>&1 ; \
	mv $${tmp_dir}/$(RELEASE_STRING).tar.gz . ; \
	rm -rf $${tmp_dir} ; \


rpm: tarball dkms.spec
	tmp_dir=`mktemp -d /tmp/dkms.XXXXXXXX` ; \
	mkdir -p $${tmp_dir}/{BUILD,RPMS,SRPMS,SPECS,SOURCES} ; \
	cp $(RELEASE_STRING).tar.gz $${tmp_dir}/SOURCES ; \
	sed "s/\[INSERT_VERSION_HERE\]/$(RELEASE_VERSION)/" dkms.spec > $${tmp_dir}/SPECS/dkms.spec ; \
	pushd $${tmp_dir} > /dev/null 2>&1; \
	rpmbuild -ba --define "_topdir $${tmp_dir}" SPECS/dkms.spec ; \
	popd > /dev/null 2>&1; \
	cp $${tmp_dir}/RPMS/noarch/* $${tmp_dir}/SRPMS/* . ; \
	rm -rf $${tmp_dir}

deb: tarball
	pdebuild --buildresult $(shell pwd)/..
