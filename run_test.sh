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

# Some helpers
dkms_status_grep_dkms_test() {
    (dkms status | grep '^dkms_test/') || true
}

check_no_dkms_test() {
    local found_moule

    found_moule="$(dkms_status_grep_dkms_test)"
    if [[ -n "$found_moule" ]] ; then
        echo >&2 'Error: module dkms_test is still in DKMS tree'
        return 1
    fi
    if [[ -d /usr/src/dkms_test-1.0 ]] ; then
        echo >&2 'Error: directory /usr/src/dkms_test-1.0 still exists'
        return 1
    fi
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
    centos | fedora | rhel | ovm)
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


echo 'Checking that the environment is clean'
check_no_dkms_test

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
cleaning build area...
make -j$(nproc) KERNELRELEASE=${KERNEL_VER} -C /lib/modules/${KERNEL_VER}/build M=/var/lib/dkms/dkms_test/1.0/build...
cleaning build area...
EOF
run_with_expected_output dkms_status_grep_dkms_test << EOF
dkms_test/1.0, ${KERNEL_VER}, $(uname -m): built
EOF

echo 'Building the test module again'
run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test/1.0 already built for kernel ${KERNEL_VER} ($(uname -m)).
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
Module dkms_test/1.0 already installed on kernel ${KERNEL_VER} ($(uname -m)).
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
cleaning build area...
make -j$(nproc) KERNELRELEASE=${KERNEL_VER} -C /lib/modules/${KERNEL_VER}/build M=/var/lib/dkms/dkms_test/1.0/build...
cleaning build area...

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
cleaning build area...
make -j$(nproc) KERNELRELEASE=${KERNEL_VER} -C /lib/modules/${KERNEL_VER}/build M=/var/lib/dkms/dkms_test/1.0/build...
cleaning build area...
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

echo 'Checking that the environment is clean again'
check_no_dkms_test

echo 'All tests successful :)'
