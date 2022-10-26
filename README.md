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
make install-debian
make install-redhat
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

Module signing
--

By default, DKMS generates a self signed certificate for signing modules at
build time and signs every module that it builds before it gets compressed in
the configured kernel compression mechanism of choice.

This requires the `openssl` command to be present on the system.

Private key and certificate are auto generated the first time DKMS is run and
placed in `/var/lib/dkms`. These certificate files can be prepulated with your
own certificates of choice.

The location as well can be changed by setting the appropriate variables in
`/etc/dkms/framework.conf`. For example, to awllow usage of the system default
Debian and Ubuntu `update-secureboot-policy` set the configuration file as
follows:
```
mok_signing_key="/var/lib/shim-signed/mok/MOK.der"
mok_certificate="/var/lib/shim-signed/mok/MOK.priv"
```

The paths specified in `mok_signing_key`, `mok_certificate` and `sign_file` can
use the variable `${kernelver}` to represent the target kernel version. 
```
sign_file="/lib/modules/${kernelver}/build/scripts/sign-file"
```

The variable `mok_signing_key` can also be a `pkcs11:...` string for a [PKCS#11
engine](https://www.rfc-editor.org/rfc/rfc7512), as long as the `sign_file`
program supports it.

Secure Boot
--

On an UEFI system with Secure Boot enabled, modules require signing (as
described in the above paragraph) before they can be loaded and the firmware of
the system must know the correct public certificate to verify the module
signature.

For importing the MOK certificate make sure `mokutil` is installed.

To check if Secure Boot is enabled:

```
# mokutil --sb-state
SecureBoot enabled
```

With the appropriate key material on the system, enroll the public key:

```
# mokutil --import /var/lib/dkms/mok.pub"
```

You'll be prompted to create a password. Enter it twice, it can also be blank.

Reboot the computer. At boot you'll see the MOK Manager EFI interface:

![SHIM UEFI key management](/images/mok-key-1.png)

Press any key to enter it, then select "Enroll MOK":

![Perform MOK management](/images/mok-key-2.png)

Then select "Continue":

![Enroll MOK](/images/mok-key-3.png)

And confirm with "Yes" when prompted:

![Enroll the key(s)?](/images/mok-key-4.png)

After this, enter the password you set up with `mokutil --import` in the previous step:

![Enroll the key(s)?](/images/mok-key-5.png)

At this point you are done, select "OK" and the computer will reboot trusting the key for your modules:

![Perform MOK management](/images/mok-key-6.png)

After reboot, you can inspect the MOK certificates with the following command:

```
# mokutil --list-enrolled | grep DKMS
        Subject: CN=DKMS module signing key
```

To check the signature on a built DKMS module that is installed on a system:

```
# modinfo dkms_test | grep ^signer
signer:         DKMS module signing key
```

The module can now be loaded without issues.

Further Documentation
--

Once DKMS is installed, you can reference its man page for further information
on different DKMS options and also to understand the formatting of a module's
dkms.conf configuration file.

The DKMS project is located at: https://github.com/dell/dkms
