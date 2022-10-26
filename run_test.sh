#!/bin/bash
# Test that dkms works properly
set -eu

# Change the to base directory
cd "$(dirname -- "$0")"

# To use a specific kernel version, use the environment variable KERNEL_VER
KERNEL_VER="${KERNEL_VER:-$(uname -r)}"
echo "Using kernel ${KERNEL_VER}"

# Override PATH to use the local dkms binary
PATH="$(pwd):$PATH"
export PATH

# temporary files and directories created during tests
TEST_TMPDIRS=(
    "/usr/src/dkms_test-1.0/"
    "/tmp/dkms_test_dir_${KERNEL_VER}/"
)
TEST_TMPFILES=(
    "/tmp/dkms_test_private_key"
    "/etc/dkms/framework.conf.d/dkms_test_framework.conf"
    "test_cmd_output.log"
    "test_cmd_expected_output.log"
)

if [ "$#" = 1 ] && [ "$1" = "--no-signing-tool" ]; then
    echo 'Ignore signing tool errors'
    NO_SIGNING_TOOL=1
    SIGNING_MESSAGE=""
else
    NO_SIGNING_TOOL=0
    SIGNING_MESSAGE=$'Signing module /var/lib/dkms/dkms_test/1.0/build/dkms_test.ko\n'
fi

# Some helpers
dkms_status_grep_dkms_test() {
    (dkms status | grep '^dkms_test/') || true
}

clean_dkms_env() {
    local found_moule

    found_moule="$(dkms_status_grep_dkms_test)"
    if [[ -n "$found_moule" ]] ; then
        dkms remove dkms_test/1.0 >/dev/null
    fi
    for dir in "${TEST_TMPDIRS[@]}"; do
        rm -rf "$dir"
    done
    for file in "${TEST_TMPFILES[@]}"; do
        rm -f "$file"
    done
}

check_no_dkms_test() {
    local found_moule

    found_moule="$(dkms_status_grep_dkms_test)"
    if [[ -n "$found_moule" ]] ; then
        echo >&2 'Error: module dkms_test is still in DKMS tree' 
        exit 1
    fi
    for dir in "${TEST_TMPDIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            echo >&2 "Error: directory ${dir} still exists"
            exit 1
        fi
    done
    for file in "${TEST_TMPFILES[@]}"; do
        if [[ -f "$file" ]]; then
            echo >&2 "Error: file ${file} still exists"
            exit 1
        fi
    done
}

run_with_expected_output() {
    cat > test_cmd_expected_output.log
    if "$@" > test_cmd_output.log 2>&1 ; then
        # "depmod..." lines can have multiple points. Replace them, to be able to compare
        sed 's/\([^.]\)\.\.\.\.*$/\1.../' -i test_cmd_output.log
        # On CentOS, weak-modules is executed. Drop it from the output, to be more generic
        sed '/^Adding any weak-modules$/d' -i test_cmd_output.log
        sed '/^Removing any linked weak-modules$/d' -i test_cmd_output.log
        # "depmod..." lines are missing when uninstalling modules on CentOS. Remove them to be more generic
        if [[ $# -ge 2 && "$2" =~ uninstall|unbuild|remove ]] ; then
            sed '/^depmod\.\.\.$/d' -i test_cmd_output.log
        fi
        # Signing related output. Drop it from the output, to be more generic
        sed '/^Sign command:/d' -i test_cmd_output.log
        sed '/^Signing key:/d' -i test_cmd_output.log
        sed '/^Public certificate (MOK):/d' -i test_cmd_output.log
        sed '/^Certificate or key are missing, generating them using update-secureboot-policy...$/d' -i test_cmd_output.log
        sed '/^Certificate or key are missing, generating self signed certificate for MOK...$/d' -i test_cmd_output.log
        if [[ "${NO_SIGNING_TOOL}" = "1" ]]; then
            sed "/^Binary .* not found, modules won't be signed$/d" -i test_cmd_output.log
            # Uncomment the following line to run this script with --no-signing-tool on platforms where the sign-file tool exists
            # sed '/^Signing module \/var\/lib\/dkms\/dkms_test\/1.0\/build\/dkms_test.ko$/d' -i test_cmd_output.log
        fi
        # OpenSSL non-critical errors while signing. Remove them to be more generic
        sed '/^At main.c:/d' -i test_cmd_output.log
        sed '/^- SSL error:/d' -i test_cmd_output.log
        if ! diff -U3 test_cmd_expected_output.log test_cmd_output.log ; then
            echo >&2 "Error: unexpected output from: $*"
            return 1
        fi
        rm test_cmd_expected_output.log test_cmd_output.log
    else
        echo "Error: command '$*' returned status $?"
        cat test_cmd_output.log
        rm test_cmd_expected_output.log test_cmd_output.log
        return 1
    fi
}

run_with_expected_error() {
    local expected_error_code="$1"
    local error_code

    shift
    cat > test_cmd_expected_output.log
    if "$@" > test_cmd_output.log 2>&1 ; then
        echo "Error: command '$*' was successful"
        cat test_cmd_output.log
        rm test_cmd_expected_output.log test_cmd_output.log
        return 1
    else
        error_code=$?
    fi
    if [[ "${error_code}" != "${expected_error_code}" ]] ; then
        echo "Error: command '$*' returned status ${error_code} instead of expected ${expected_error_code}"
        cat test_cmd_output.log
        rm test_cmd_expected_output.log test_cmd_output.log
        return 1
    fi
    if ! diff -U3 test_cmd_expected_output.log test_cmd_output.log ; then
        echo >&2 "Error: unexpected output from: $*"
        return 1
    fi
    rm test_cmd_expected_output.log test_cmd_output.log
}

# Compute the expected destination module location
os_id="$(sed -n 's/^ID\s*=\s*\(.*\)$/\1/p' /etc/os-release | tr -d '"')"
mod_compression_ext=
case "${os_id}" in
    centos | fedora | rhel | ovm | almalinux)
        expected_dest_loc=extra
        mod_compression_ext=.xz
        ;;
    sles | suse | opensuse)
        expected_dest_loc=updates
        ;;
    arch | debian | ubuntu)
        expected_dest_loc=updates/dkms
        ;;
    alpine)
        expected_dest_loc=kernel/extra
        ;;
    *)
        echo >&2 "Error: unknown Linux distribution ID ${os_id}"
        exit 1
        ;;
esac


echo 'Preparing a clean environment'
clean_dkms_env

echo 'Test framework file hijacking'
mkdir -p /etc/dkms/framework.conf.d/
cp test/framework/hijacking.conf /etc/dkms/framework.conf.d/dkms_test_framework.conf
run_with_expected_output dkms status -m dkms_test << EOF
EOF
rm /etc/dkms/framework.conf.d/dkms_test_framework.conf

echo 'Adding the test module by version (expected error)'
run_with_expected_error 2 dkms add -m dkms_test -v 1.0 << EOF
Error! Could not find module source directory.
Directory: /usr/src/dkms_test-1.0 does not exist.
EOF

echo 'Adding the test module by directory'
run_with_expected_output dkms add test/dkms_test-1.0 << EOF
Creating symlink /var/lib/dkms/dkms_test/1.0/source -> /usr/src/dkms_test-1.0
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
dkms_test/1.0: added
EOF
if ! [[ -d /usr/src/dkms_test-1.0 ]] ; then
    echo >&2 'Error: directory /usr/src/dkms_test-1.0 was not created'
    return 1
fi

echo 'Adding the test module again (expected error)'
run_with_expected_error 3 dkms add test/dkms_test-1.0 << EOF
Error! DKMS tree already contains: dkms_test-1.0
You cannot add the same module/version combo more than once.
EOF

echo 'Adding the test module by version (expected error)'
run_with_expected_error 3 dkms add -m dkms_test -v 1.0 << EOF
Error! DKMS tree already contains: dkms_test-1.0
You cannot add the same module/version combo more than once.
EOF

echo 'Building the test module'
run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF

Building module:
Cleaning build area...
make -j$(nproc) KERNELRELEASE=${KERNEL_VER} -C /lib/modules/${KERNEL_VER}/build M=/var/lib/dkms/dkms_test/1.0/build...
${SIGNING_MESSAGE}Cleaning build area...
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
dkms_test/1.0, ${KERNEL_VER}, $(uname -m): built
EOF

echo 'Building the test module again'
run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test/1.0 already built for kernel ${KERNEL_VER} ($(uname -m)), skip. You may override by specifying --force.
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
dkms_test/1.0, ${KERNEL_VER}, $(uname -m): built
EOF

if [[ "${NO_SIGNING_TOOL}" = 0 ]]; then
    echo 'Building the test module with bad sign_file path in framework file'
    cp test/framework/bad_sign_file_path.conf /etc/dkms/framework.conf.d/dkms_test_framework.conf
    run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 --force << EOF
Binary /no/such/file not found, modules won't be signed

Building module:
Cleaning build area...
make -j$(nproc) KERNELRELEASE=${KERNEL_VER} -C /lib/modules/${KERNEL_VER}/build M=/var/lib/dkms/dkms_test/1.0/build...
Cleaning build area...
EOF

    echo 'Building the test module with bad mok_signing_key path in framework file'
    cp test/framework/bad_key_file_path.conf /etc/dkms/framework.conf.d/dkms_test_framework.conf
    run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 --force << EOF
Key file /no/such/path.key not found and can't be generated, modules won't be signed

Building module:
Cleaning build area...
make -j$(nproc) KERNELRELEASE=${KERNEL_VER} -C /lib/modules/${KERNEL_VER}/build M=/var/lib/dkms/dkms_test/1.0/build...
Cleaning build area...
EOF

    echo 'Building the test module with bad mok_certificate path in framework file'
    cp test/framework/bad_cert_file_path.conf /etc/dkms/framework.conf.d/dkms_test_framework.conf
    run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 --force << EOF
Certificate file /no/such/path.crt not found and can't be generated, modules won't be signed

Building module:
Cleaning build area...
make -j$(nproc) KERNELRELEASE=${KERNEL_VER} -C /lib/modules/${KERNEL_VER}/build M=/var/lib/dkms/dkms_test/1.0/build...
Cleaning build area...
EOF
    rm /tmp/dkms_test_private_key

    echo 'Building the test module with path contains variables in framework file'
    mkdir "/tmp/dkms_test_dir_${KERNEL_VER}/"
    cp test/framework/variables_in_path.conf /etc/dkms/framework.conf.d/dkms_test_framework.conf
    run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 --force << EOF

Building module:
Cleaning build area...
make -j$(nproc) KERNELRELEASE=${KERNEL_VER} -C /lib/modules/${KERNEL_VER}/build M=/var/lib/dkms/dkms_test/1.0/build...
${SIGNING_MESSAGE}Cleaning build area...
EOF
    rm -r "/tmp/dkms_test_dir_${KERNEL_VER}/"

    rm /etc/dkms/framework.conf.d/dkms_test_framework.conf
fi

echo 'Building the test module again by force'
run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 --force << EOF

Building module:
Cleaning build area...
make -j$(nproc) KERNELRELEASE=${KERNEL_VER} -C /lib/modules/${KERNEL_VER}/build M=/var/lib/dkms/dkms_test/1.0/build...
${SIGNING_MESSAGE}Cleaning build area...
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
dkms_test/1.0, ${KERNEL_VER}, $(uname -m): built
EOF


echo 'Installing the test module'
run_with_expected_output dkms install -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF

dkms_test.ko${mod_compression_ext}:
Running module version sanity check.
 - Original module
   - No original module exists within this kernel
 - Installation
   - Installing to /lib/modules/${KERNEL_VER}/${expected_dest_loc}/
depmod...
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
dkms_test/1.0, ${KERNEL_VER}, $(uname -m): installed
EOF

echo 'Installing the test module again'
run_with_expected_output dkms install -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test/1.0 already installed on kernel ${KERNEL_VER} ($(uname -m)), skip. You may override by specifying --force.
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
dkms_test/1.0, ${KERNEL_VER}, $(uname -m): installed
EOF
if ! [[ -f "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}" ]] ; then
    echo >&2 "Error: module not found in /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}"
    exit 1
fi

echo 'Installing the test module again by force'
run_with_expected_output dkms install -k "${KERNEL_VER}" -m dkms_test -v 1.0 --force << EOF
Module dkms_test-1.0 for kernel ${KERNEL_VER} ($(uname -m)).
Before uninstall, this module version was ACTIVE on this kernel.

dkms_test.ko${mod_compression_ext}:
 - Uninstallation
   - Deleting from: /lib/modules/${KERNEL_VER}/${expected_dest_loc}/
 - Original module
   - No original module was found for this module on this kernel.
   - Use the dkms install command to reinstall any previous module version.
depmod...

dkms_test.ko${mod_compression_ext}:
Running module version sanity check.
 - Original module
   - No original module exists within this kernel
 - Installation
   - Installing to /lib/modules/${KERNEL_VER}/${expected_dest_loc}/
depmod...
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
dkms_test/1.0, ${KERNEL_VER}, $(uname -m): installed
EOF

echo 'Checking modinfo'
run_with_expected_output sh -c "modinfo /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext} | head -n 4" << EOF
filename:       /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}
version:        1.0
description:    A Simple dkms test module
license:        GPL
EOF

if [[ "${NO_SIGNING_TOOL}" = 0 ]]; then
    echo 'Checking module signature'
    run_with_expected_output sh -c "modinfo /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext} | grep ^sig_key | cut -f1 -d' '" << EOF
sig_key:
EOF
fi

echo 'Uninstalling the test module'
run_with_expected_output dkms uninstall -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test-1.0 for kernel ${KERNEL_VER} ($(uname -m)).
Before uninstall, this module version was ACTIVE on this kernel.

dkms_test.ko${mod_compression_ext}:
 - Uninstallation
   - Deleting from: /lib/modules/${KERNEL_VER}/${expected_dest_loc}/
 - Original module
   - No original module was found for this module on this kernel.
   - Use the dkms install command to reinstall any previous module version.
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
dkms_test/1.0, ${KERNEL_VER}, $(uname -m): built
EOF
if [[ -e "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}" ]] ; then
    echo >&2 "Error: module not removed in /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}"
    exit 1
fi

echo 'Uninstalling the test module again'
run_with_expected_output dkms uninstall -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test 1.0 is not installed for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
dkms_test/1.0, ${KERNEL_VER}, $(uname -m): built
EOF

echo 'Unbuilding the test module'
run_with_expected_output dkms unbuild -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test 1.0 is not installed for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
dkms_test/1.0: added
EOF

echo 'Unbuilding the test module again'
run_with_expected_output dkms unbuild -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test 1.0 is not installed for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
Module dkms_test 1.0 is not built for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
dkms_test/1.0: added
EOF

echo 'Removing the test module'
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test 1.0 is not installed for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
Module dkms_test 1.0 is not built for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
Deleting module dkms_test-1.0 completely from the DKMS tree.
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
EOF
if ! [[ -d /usr/src/dkms_test-1.0 ]] ; then
    echo >&2 'Error: directory /usr/src/dkms_test-1.0 was removed'
    return 1
fi

echo 'Adding the test module by version'
run_with_expected_output dkms add -m dkms_test -v 1.0 << EOF
Creating symlink /var/lib/dkms/dkms_test/1.0/source -> /usr/src/dkms_test-1.0
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
dkms_test/1.0: added
EOF

echo 'Removing the test module'
run_with_expected_output dkms remove --all -m dkms_test -v 1.0 << EOF
Deleting module dkms_test-1.0 completely from the DKMS tree.
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
EOF

echo 'Installing the test module by version (combining add, build, install)'
run_with_expected_output dkms install -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Creating symlink /var/lib/dkms/dkms_test/1.0/source -> /usr/src/dkms_test-1.0

Building module:
Cleaning build area...
make -j$(nproc) KERNELRELEASE=${KERNEL_VER} -C /lib/modules/${KERNEL_VER}/build M=/var/lib/dkms/dkms_test/1.0/build...
${SIGNING_MESSAGE}Cleaning build area...

dkms_test.ko${mod_compression_ext}:
Running module version sanity check.
 - Original module
   - No original module exists within this kernel
 - Installation
   - Installing to /lib/modules/${KERNEL_VER}/${expected_dest_loc}/
depmod...
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
dkms_test/1.0, ${KERNEL_VER}, $(uname -m): installed
EOF
if ! [[ -f "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}" ]] ; then
    echo >&2 "Error: module not found in /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}"
    exit 1
fi

echo 'Checking modinfo'
run_with_expected_output sh -c "modinfo /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext} | head -n 4" << EOF
filename:       /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}
version:        1.0
description:    A Simple dkms test module
license:        GPL
EOF

if [[ "${NO_SIGNING_TOOL}" = 0 ]]; then
    echo 'Checking module signature'
    run_with_expected_output sh -c "modinfo /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext} | grep ^sig_key | cut -f1 -d' '" << EOF
sig_key:
EOF
fi

echo 'Removing the test module with --all'
run_with_expected_output dkms remove --all -m dkms_test -v 1.0 << EOF
Module dkms_test-1.0 for kernel ${KERNEL_VER} ($(uname -m)).
Before uninstall, this module version was ACTIVE on this kernel.

dkms_test.ko${mod_compression_ext}:
 - Uninstallation
   - Deleting from: /lib/modules/${KERNEL_VER}/${expected_dest_loc}/
 - Original module
   - No original module was found for this module on this kernel.
   - Use the dkms install command to reinstall any previous module version.
Deleting module dkms_test-1.0 completely from the DKMS tree.
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
EOF
if [[ -e "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}" ]] ; then
    echo >&2 "Error: module not removed in /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}"
    exit 1
fi

echo 'Removing /usr/src/dkms_test-1.0'
rm -r /usr/src/dkms_test-1.0

echo 'Building the test module by config file (combining add, build)'
run_with_expected_output dkms build -k "${KERNEL_VER}" test/dkms_test-1.0/dkms.conf << EOF
Creating symlink /var/lib/dkms/dkms_test/1.0/source -> /usr/src/dkms_test-1.0

Building module:
Cleaning build area...
make -j$(nproc) KERNELRELEASE=${KERNEL_VER} -C /lib/modules/${KERNEL_VER}/build M=/var/lib/dkms/dkms_test/1.0/build...
${SIGNING_MESSAGE}Cleaning build area...
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
dkms_test/1.0, ${KERNEL_VER}, $(uname -m): built
EOF

echo "Running dkms autoinstall"
run_with_expected_output dkms autoinstall -k "${KERNEL_VER}" << EOF

dkms_test.ko${mod_compression_ext}:
Running module version sanity check.
 - Original module
   - No original module exists within this kernel
 - Installation
   - Installing to /lib/modules/${KERNEL_VER}/${expected_dest_loc}/
depmod...
EOF

echo 'Removing the test module with --all'
run_with_expected_output dkms remove --all -m dkms_test -v 1.0 << EOF
Module dkms_test-1.0 for kernel ${KERNEL_VER} ($(uname -m)).
Before uninstall, this module version was ACTIVE on this kernel.

dkms_test.ko${mod_compression_ext}:
 - Uninstallation
   - Deleting from: /lib/modules/${KERNEL_VER}/${expected_dest_loc}/
 - Original module
   - No original module was found for this module on this kernel.
   - Use the dkms install command to reinstall any previous module version.
Deleting module dkms_test-1.0 completely from the DKMS tree.
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
EOF

echo 'Removing /usr/src/dkms_test-1.0'
rm -r /usr/src/dkms_test-1.0

echo 'Checking that the environment is clean'
check_no_dkms_test

echo 'All tests successful :)'
