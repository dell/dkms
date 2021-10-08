Dynamic Kernel Module System (DKMS)
==
This intention of this README is to explain how DKMS can be used in conjunction
with tarballs which contain a dkms.conf file within them.

The DKMS project (and any updates) can be found at: https://github.com/dell/dkms

Installation
--

Installation is performed from the source directory with one of the following
commands:

```
make install
make install_debian
make install-redhat-systemd
```

Distribution specific installations (RPM, DEB, etc.) are not contained in this
source repository.


Installation via DKMS Tarballs
--

DKMS can install directly from the following:

1. Generic module source tarballs which contain a dkms.conf file
2. Specially created DKMS tarballs with module source, pre-built module
   binaries and a dkms.conf file
3. Specially created DKMS tarballs with pre-built module binaries and a
   dkms.conf file
4. Manual placement of module source and dkms.conf file into
   `/usr/src/<module>-<moduleversion>/` directory

In order to load any tarball into the DKMS tree, you must use the following
command:

```
# dkms ldtarball /path/to/dkms_enabled.tar.gz
```

This command will first inspect the tarball to ensure that it contains a
dkms.conf configuration file for that module.  If it cannot find this file
anywhere within the archive, then the ldtarball will fail.

From here, it will place the source in the tarball into
`/usr/src/<module>-<moduleversion>/`. If source already exists in the directory,
it will not overwrite it unless the --force option is specified. If the tarball
is of type "c" above and does not contain source, it will only continue to load
the tarball if existing module source is found in
`/usr/src/<module>-<moduleversion>/` or if the --force option is specified.

Continuing on, if the tarball is of type "b" or "c" it will then load any
pre-built binaries found within the tarball into the dkms tree, but will stop
short of installing them.  Thus, all pre-built binaries will then be of in the
*built* state when checked from the `dkms status` command.  You can then use the
`dkms install` command to install any of these binaries.

To create a tarball of type "1" above, you need only to take module source and a
dkms.conf file for that module and create a tarball from them.  Tarballs of
type *2* or type *3* are created with the `dkms mktarball` command.  To create
a type *3* tarball, you must specify the flag `--binaries-only` with the
`mktarball`.



Installation on Systems with no Module Source and/or Compiler
--

If you choose not to load module source on your system or if you choose not to
load a compiler such as gcc onto your system, DKMS can still be used to install
modules.  It does this through use of DKMS binary only tarballs as explained in
this README under tarballs of type *c*.

If your system does not have module source, loading the dkms tarball will fail
because of this.  To avoid this, use the --force flag, as such:

```
# dkms ldtarball /path/to/dkms_enabled.tar.gz --force
```

This will load the pre-built binaries into the dkms tree, and create the
directory `/usr/src/<module>-<moduleversion>/` which will only contain the
module's dkms.conf configuration file.  Once the tarball is loaded, you can then
use `dkms install` to install any of the pre-built modules.

Of course, since module source will not be located in your dkms tree, you will
not be able to build any modules with DKMS for this package.


Further Documentation
--

Once DKMS is installed, you can reference its man page for further information
on different DKMS options and also to understand the formatting of a module's
dkms.conf configuration file.

You may also wish to join the dkms-devel public mailing-list at
http://lists.us.dell.com/.

The DKMS project is located at: https://github.com/dell/dkms


Module signing
--

On an UEFI system with Secure Boot enabled, modules require signing before they
can be loaded. First of all make sure the commands `openssl` and `mokutil` are
installed.

For further customizations (scripts, certificates, etc.) please refer to the
manual page (`dkms(8)`).

To check if Secure Boot is enabled:

```
# mokutil --sb-state
SecureBoot enabled
```

To proceed with Signing with the standard settings, proceed as follows.

First uncomment the `sign_tool` line in `/etc/dkms/framework.conf`, this allow
using the script declared in that variable as a hook during the module build
process for signing modules:

```
sign_tool="/etc/dkms/sign_helper.sh"
```

The script by defaults expects a private key and a matching certificate in the
`root` home folder. To generate the key and the self signed certificate:

```
# openssl req -new -x509 -nodes -days 36500 -subj "/CN=DKMS modules" \
    -newkey rsa:2048 -keyout /root/dkms.key \
    -outform DER -out /root/dkms.der
```

After generating the key, enroll the public key:

```
# mokutil --import /root/dkms.der
```

You'll be prompted to create a password. Enter it twice, it can also be blank.

Reboot the computer. At boot you'll see the MOK Manager EFI interface, press any
key to enter it.

- "Enroll MOK"
- "Continue".
- "Yes".
- Enter the password you set up just now.
- Select "OK" and the computer will reboot again.

After reboot, you can inspect the MOK certificates with the following command:

```
# mokutil --list-enrolled | grep DKMS
        Subject: CN=DKMS modules
```

To check the signature on a built DKMS module that is installed on a system:

```
# modinfo dkms_test | grep ^signer
signer:         DKMS modules
```

The module should be able to be loaded without issues.
