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

# temporary files, directories, and modules created during tests
TEST_MODULES=(
    "dkms_test"
    "dkms_failing_test"
    "dkms_dependencies_test"
    "dkms_multiver_test"
)
TEST_TMPDIRS=(
    "/usr/src/dkms_test-1.0/"
    "/usr/src/dkms_failing_test-1.0/"
    "/usr/src/dkms_dependencies_test-1.0"
    "/usr/src/dkms_multiver_test-1.0"
    "/usr/src/dkms_multiver_test-2.0"
    "/tmp/dkms_test_dir_${KERNEL_VER}/"
)
TEST_TMPFILES=(
    "/tmp/dkms_test_private_key"
    "/tmp/dkms_test_certificate"
    "/tmp/dkms_test_kconfig"
    "/etc/dkms/framework.conf.d/dkms_test_framework.conf"
    "test_cmd_output.log"
    "test_cmd_expected_output.log"
)

SIGNING_MESSAGE=""
if [ "$#" = 1 ] && [ "$1" = "--no-signing-tool" ]; then
    echo 'Ignore signing tool errors'
    NO_SIGNING_TOOL=1
else
    NO_SIGNING_TOOL=0
fi

# Some helpers
dkms_status_grep_dkms_module() {
    local module_name="$1"
    (dkms status | grep "^${module_name}/") || true
}

clean_dkms_env() {
    local found_module

    for module in ${TEST_MODULES[@]}; do
        found_module="$(dkms_status_grep_dkms_module ${module})"
        if [[ -n "$found_module" ]] ; then
            dkms remove ${module}/1.0 >/dev/null
        fi
        rm -rf "/var/lib/dkms/${module}/"
        rm -f "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/${module}.ko${mod_compression_ext}"
    done
    for dir in "${TEST_TMPDIRS[@]}"; do
        rm -rf "$dir"
    done
    for file in "${TEST_TMPFILES[@]}"; do
        rm -f "$file"
    done
}

check_no_dkms_test() {
    local found_module

    for module in ${TEST_MODULES[@]}; do
        found_module="$(dkms_status_grep_dkms_module ${module})"
        if [[ -n "$found_module" ]] ; then
            echo >&2 "Error: module ${module} is still in DKMS tree"
            exit 1
        fi
        if [[ -d "/var/lib/dkms/${module}" ]]; then
            echo >&2 "Error: directory /var/lib/dkms/${module} still exists"
            exit 1
        fi
        if [[ -f "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/${module}.ko${mod_compression_ext}" ]]; then
            echo >&2 "Error: file /lib/modules/${KERNEL_VER}/${expected_dest_loc}/${module}.ko${mod_compression_ext} still exists"
            exit 1
        fi
    done
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

cert_serial() {
    local ver="$(openssl version)"
    # Some systems in CI test are still using ancient versions of openssl program.
    if [[ "$ver" = "OpenSSL 1.0."* ]] || [[ "$ver" = "OpenSSL 0."* ]]; then
        openssl x509 -text -inform DER -in "$1" -noout | grep -A 1 'X509v3 Subject Key Identifier' | tail -n 1 | tr 'a-z' 'A-Z' | tr -d ' :'
    else
        openssl x509 -serial -inform DER -in "$1" -noout | tr 'a-z' 'A-Z' | sed 's/^SERIAL=//'
    fi
}

set_signing_message() {
    # $1: module name
    # $2: module version
    # $3: module file name if not the same as $1
    if [[ "$NO_SIGNING_TOOL" = 0 ]]; then
        SIGNING_MESSAGE="Signing module /var/lib/dkms/$1/$2/build/${3:-$1}.ko"$'\n'
    fi
}

run_status_with_expected_output() {
    local module=$1

    cat > test_cmd_expected_output.log
    if dkms_status_grep_dkms_module "${module}" > test_cmd_output.log 2>&1 ; then
        if ! diff -U3 test_cmd_expected_output.log test_cmd_output.log ; then
            echo >&2 "Error: unexpected output from: dkms_status_grep_dkms_module for ${module}"
            return 1
        fi
        rm test_cmd_expected_output.log test_cmd_output.log
    else
        echo "Error: dkms status for ${module} returned status $?"
        cat test_cmd_output.log
        rm test_cmd_expected_output.log test_cmd_output.log
        return 1
    fi
}

genericize_expected_output() {
    local output_log=$1

    # "depmod..." lines can have multiple points. Replace them, to be able to compare
    sed -i 's/\([^.]\)\.\.\.\.*$/\1.../' ${output_log}
    # On CentOS, weak-modules is executed. Drop it from the output, to be more generic
    sed -i '/^Adding any weak-modules$/d' ${output_log}
    sed -i '/^Removing any linked weak-modules$/d' ${output_log}
    # "depmod..." lines are missing when uninstalling modules on CentOS. Remove them to be more generic
    if [[ $# -ge 2 && "$2" =~ uninstall|unbuild|remove ]] ; then
        sed -i '/^depmod\.\.\.$/d' ${output_log}
    fi
    # Signing related output. Drop it from the output, to be more generic
    sed -i '/^Sign command:/d' ${output_log}
    sed -i '/^Signing key:/d' ${output_log}
    sed -i '/^Public certificate (MOK):/d' ${output_log}
    sed -i '/^Certificate or key are missing, generating them using update-secureboot-policy...$/d' ${output_log}
    sed -i '/^Certificate or key are missing, generating self signed certificate for MOK...$/d' ${output_log}
    if [[ "${NO_SIGNING_TOOL}" = "1" ]]; then
        sed -i "/^Binary .* not found, modules won't be signed$/d" ${output_log}
        # Uncomment the following line to run this script with --no-signing-tool on platforms where the sign-file tool exists
        # sed -i '/^Signing module \/var\/lib\/dkms\/dkms_test\/1.0\/build\/dkms_test.ko$/d' ${output_log}
    fi
    # OpenSSL non-critical errors while signing. Remove them to be more generic
    sed -i '/^At main.c:/d' ${output_log}
    sed -i '/^- SSL error:/d' ${output_log}
    # Apport related error that can occur in the CI. Drop from the output to be more generic
    sed -i "/^python3: can't open file '\/usr\/share\/apport\/package-hooks\/dkms_packages.py'\: \[Errno 2\] No such file or directory$/d" ${output_log}
    sed -i "/^ERROR (dkms apport): /d" ${output_log}
}

run_with_expected_output() {
    local dkms_command="$2"
    local output_log=test_cmd_output.log
    local expected_output_log=test_cmd_expected_output.log

    cat > ${expected_output_log}
    if "$@" > ${output_log} 2>&1 ; then
        genericize_expected_output ${output_log} ${dkms_command}
        if ! diff -U3 ${expected_output_log} ${output_log} ; then
            echo >&2 "Error: unexpected output from: $*"
            return 1
        fi
        rm ${expected_output_log} ${output_log}
    else
        echo "Error: command '$*' returned status $?"
        cat ${output_log}
        rm ${expected_output_log} ${output_log}
        return 1
    fi
}

run_with_expected_error() {
    local expected_error_code="$1"
    local dkms_command="$2"
    local output_log=test_cmd_output.log
    local expected_output_log=test_cmd_expected_output.log
    local error_code

    shift
    cat > ${expected_output_log}
    if "$@" > ${output_log} 2>&1 ; then
        echo "Error: command '$*' was successful"
        cat ${output_log}
        rm ${expected_output_log} ${output_log}
        return 1
    else
        error_code=$?
    fi
    if [[ "${error_code}" != "${expected_error_code}" ]] ; then
        echo "Error: command '$*' returned status ${error_code} instead of expected ${expected_error_code}"
        cat ${output_log}
        rm ${expected_output_log} ${output_log}
        return 1
    fi
    genericize_expected_output ${output_log} ${dkms_command}
    if ! diff -U3 ${expected_output_log} ${output_log} ; then
        echo >&2 "Error: unexpected output from: $*"
        return 1
    fi
    rm ${expected_output_log} ${output_log}
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


echo 'Preparing a clean test environment'
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
run_status_with_expected_output 'dkms_test' << EOF
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
set_signing_message "dkms_test" "1.0"
run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF

Building module:
Cleaning build area...
make -j$(nproc) KERNELRELEASE=${KERNEL_VER} -C /lib/modules/${KERNEL_VER}/build M=/var/lib/dkms/dkms_test/1.0/build...
${SIGNING_MESSAGE}Cleaning build area...
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0, ${KERNEL_VER}, $(uname -m): built
EOF

echo 'Building the test module again'
run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test/1.0 already built for kernel ${KERNEL_VER} ($(uname -m)), skip. You may override by specifying --force.
EOF
run_status_with_expected_output 'dkms_test' << EOF
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

    BUILT_MODULE_PATH="/var/lib/dkms/dkms_test/1.0/${KERNEL_VER}/$(uname -m)/module/dkms_test.ko${mod_compression_ext}"
    # If sig_key can't be extracted from module, the hash algorithm is also unknown
    # sig_hashalgo itself may show bogus value if kmod version < 26
    if [[ "$(modinfo "${BUILT_MODULE_PATH}" | grep '^sig_key:' | tr -d ' ')" != "sig_key:" ]]; then
        echo 'Building the test module using a different hash algorithm'
        cp test/framework/temp_key_cert.conf /etc/dkms/framework.conf.d/dkms_test_framework.conf
        CURRENT_HASH="$(modinfo "${BUILT_MODULE_PATH}" | grep '^sig_hashalgo:' | sed 's/sig_hashalgo: *//')"
        if [[ "${CURRENT_HASH}" == "sha512" ]]; then
            ALTER_HASH="sha256"
        else
            ALTER_HASH="sha512"
        fi
        echo "CONFIG_MODULE_SIG_HASH=\"${ALTER_HASH}\"" > /tmp/dkms_test_kconfig
        run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 --config /tmp/dkms_test_kconfig --force << EOF

Building module:
Cleaning build area...
make -j$(nproc) KERNELRELEASE=${KERNEL_VER} -C /lib/modules/${KERNEL_VER}/build M=/var/lib/dkms/dkms_test/1.0/build...
${SIGNING_MESSAGE}Cleaning build area...
EOF
        run_with_expected_output sh -c "modinfo '${BUILT_MODULE_PATH}' | grep '^sig_hashalgo:' | tr -d ' '" << EOF
sig_hashalgo:${ALTER_HASH}
EOF
        rm /tmp/dkms_test_kconfig
    fi

    rm /etc/dkms/framework.conf.d/dkms_test_framework.conf
fi

cp test/framework/temp_key_cert.conf /etc/dkms/framework.conf.d/dkms_test_framework.conf

echo 'Building the test module again by force'
run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 --force << EOF

Building module:
Cleaning build area...
make -j$(nproc) KERNELRELEASE=${KERNEL_VER} -C /lib/modules/${KERNEL_VER}/build M=/var/lib/dkms/dkms_test/1.0/build...
${SIGNING_MESSAGE}Cleaning build area...
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0, ${KERNEL_VER}, $(uname -m): built
EOF

if [[ "${NO_SIGNING_TOOL}" = 0 ]]; then
    echo 'Extracting serial number from the certificate'
    MODULE_SERIAL="$(cert_serial /tmp/dkms_test_certificate)"
fi

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
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0, ${KERNEL_VER}, $(uname -m): installed
EOF

echo 'Installing the test module again'
run_with_expected_output dkms install -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test/1.0 already installed on kernel ${KERNEL_VER} ($(uname -m)), skip. You may override by specifying --force.
EOF
run_status_with_expected_output 'dkms_test' << EOF
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
run_status_with_expected_output 'dkms_test' << EOF
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
    SIG_KEY="$(modinfo "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}" | grep '^sig_key:')"
    run_with_expected_output sh -c "echo '${SIG_KEY}' | cut -f1 -d' '" << EOF
sig_key:
EOF
    if [[ "${SIG_KEY// /}" = "sig_key:" ]]; then
        # kmod may not be linked with openssl and thus can't extract the key from module
        echo "Warning: module was signed but the key is unknown"
    else
        run_with_expected_output sh -c "echo '${SIG_KEY}' | tr -d ' :'" << EOF
sig_key${MODULE_SERIAL}
EOF
    fi
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
run_status_with_expected_output 'dkms_test' << EOF
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
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0, ${KERNEL_VER}, $(uname -m): built
EOF

echo 'Unbuilding the test module'
run_with_expected_output dkms unbuild -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test 1.0 is not installed for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0: added
EOF

echo 'Unbuilding the test module again'
run_with_expected_output dkms unbuild -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test 1.0 is not installed for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
Module dkms_test 1.0 is not built for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0: added
EOF

echo 'Removing the test module'
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test 1.0 is not installed for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
Module dkms_test 1.0 is not built for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
Deleting module dkms_test-1.0 completely from the DKMS tree.
EOF
run_status_with_expected_output 'dkms_test' << EOF
EOF
if ! [[ -d /usr/src/dkms_test-1.0 ]] ; then
    echo >&2 'Error: directory /usr/src/dkms_test-1.0 was removed'
    return 1
fi

echo 'Adding the test module by version'
run_with_expected_output dkms add -m dkms_test -v 1.0 << EOF
Creating symlink /var/lib/dkms/dkms_test/1.0/source -> /usr/src/dkms_test-1.0
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0: added
EOF

echo 'Removing the test module'
run_with_expected_output dkms remove --all -m dkms_test -v 1.0 << EOF
Deleting module dkms_test-1.0 completely from the DKMS tree.
EOF
run_status_with_expected_output 'dkms_test' << EOF
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
run_status_with_expected_output 'dkms_test' << EOF
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
    SIG_KEY="$(modinfo "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}" | grep '^sig_key:')"
    run_with_expected_output sh -c "echo '${SIG_KEY}' | cut -f1 -d' '" << EOF
sig_key:
EOF
    if [[ "${SIG_KEY// /}" = "sig_key:" ]]; then
        # kmod may not be linked with openssl and thus can't extract the key from module
        echo "Warning: module was signed but the key is unknown"
    else
        run_with_expected_output sh -c "echo '${SIG_KEY}' | tr -d ' :'" << EOF
sig_key${MODULE_SERIAL}
EOF
    fi
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
run_status_with_expected_output 'dkms_test' << EOF
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
run_status_with_expected_output 'dkms_test' << EOF
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
run_status_with_expected_output 'dkms_test' << EOF
EOF

echo 'Removing temporary files'
if [[ "${NO_SIGNING_TOOL}" = 0 ]]; then
    rm /tmp/dkms_test_private_key /tmp/dkms_test_certificate
fi
rm /etc/dkms/framework.conf.d/dkms_test_framework.conf

echo 'Removing /usr/src/dkms_test-1.0'
rm -r /usr/src/dkms_test-1.0

echo 'Adding the multiver test modules by directory'
run_with_expected_output dkms add test/dkms_multiver_test/1.0 << EOF
Creating symlink /var/lib/dkms/dkms_multiver_test/1.0/source -> /usr/src/dkms_multiver_test-1.0
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0: added
EOF
if ! [[ -d /usr/src/dkms_multiver_test-1.0 ]] ; then
    echo >&2 'Error: directory /usr/src/dkms_multiver_test-1.0 was not created'
    exit 1
fi
run_with_expected_output dkms add test/dkms_multiver_test/2.0 << EOF
Creating symlink /var/lib/dkms/dkms_multiver_test/2.0/source -> /usr/src/dkms_multiver_test-2.0
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0: added
dkms_multiver_test/2.0: added
EOF
if ! [[ -d /usr/src/dkms_multiver_test-1.0 ]] ; then
    echo >&2 'Error: directory /usr/src/dkms_multiver_test-2.0 was not created'
    exit 1
fi

echo 'Building the multiver test modules'
set_signing_message "dkms_multiver_test" "1.0"
run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_multiver_test -v 1.0 << EOF

Building module:
Cleaning build area...
make -j$(nproc) KERNELRELEASE=${KERNEL_VER} -C /lib/modules/${KERNEL_VER}/build M=/var/lib/dkms/dkms_multiver_test/1.0/build...
${SIGNING_MESSAGE}Cleaning build area...
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0, ${KERNEL_VER}, $(uname -m): built
dkms_multiver_test/2.0: added
EOF
set_signing_message "dkms_multiver_test" "2.0"
run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_multiver_test -v 2.0 << EOF

Building module:
Cleaning build area...
make -j$(nproc) KERNELRELEASE=${KERNEL_VER} -C /lib/modules/${KERNEL_VER}/build M=/var/lib/dkms/dkms_multiver_test/2.0/build...
${SIGNING_MESSAGE}Cleaning build area...
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0, ${KERNEL_VER}, $(uname -m): built
dkms_multiver_test/2.0, ${KERNEL_VER}, $(uname -m): built
EOF

echo 'Installing the multiver test modules'
run_with_expected_output dkms install -k "${KERNEL_VER}" -m dkms_multiver_test -v 1.0 << EOF

dkms_multiver_test.ko${mod_compression_ext}:
Running module version sanity check.
 - Original module
   - No original module exists within this kernel
 - Installation
   - Installing to /lib/modules/${KERNEL_VER}/${expected_dest_loc}/
depmod...
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0, ${KERNEL_VER}, $(uname -m): installed
dkms_multiver_test/2.0, ${KERNEL_VER}, $(uname -m): built
EOF
run_with_expected_output dkms install -k "${KERNEL_VER}" -m dkms_multiver_test -v 2.0 << EOF

dkms_multiver_test.ko${mod_compression_ext}:
Running module version sanity check.
 - Original module
   - This kernel never originally had a module by this name
 - Installation
   - Installing to /lib/modules/${KERNEL_VER}/${expected_dest_loc}/
depmod...
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0, ${KERNEL_VER}, $(uname -m): built
dkms_multiver_test/2.0, ${KERNEL_VER}, $(uname -m): installed
EOF
run_with_expected_error 6 dkms install -k "${KERNEL_VER}" -m dkms_multiver_test -v 1.0 << EOF

dkms_multiver_test.ko${mod_compression_ext}:
Running module version sanity check.
Error! Module version 1.0 for dkms_multiver_test.ko${mod_compression_ext}
is not newer than what is already found in kernel ${KERNEL_VER} (2.0).
You may override by specifying --force.
Error! Installation aborted.
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0, ${KERNEL_VER}, $(uname -m): built
dkms_multiver_test/2.0, ${KERNEL_VER}, $(uname -m): installed
EOF

echo 'Uninstalling the multiver test modules'
run_with_expected_output dkms uninstall -k "${KERNEL_VER}" -m dkms_multiver_test -v 1.0 << EOF
Module dkms_multiver_test 1.0 is not installed for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0, ${KERNEL_VER}, $(uname -m): built
dkms_multiver_test/2.0, ${KERNEL_VER}, $(uname -m): installed
EOF
run_with_expected_output dkms uninstall -k "${KERNEL_VER}" -m dkms_multiver_test -v 2.0 << EOF
Module dkms_multiver_test-2.0 for kernel ${KERNEL_VER} ($(uname -m)).
Before uninstall, this module version was ACTIVE on this kernel.

dkms_multiver_test.ko${mod_compression_ext}:
 - Uninstallation
   - Deleting from: /lib/modules/${KERNEL_VER}/${expected_dest_loc}/
 - Original module
   - No original module was found for this module on this kernel.
   - Use the dkms install command to reinstall any previous module version.
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0, ${KERNEL_VER}, $(uname -m): built
dkms_multiver_test/2.0, ${KERNEL_VER}, $(uname -m): built
EOF
if [[ -e "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_multiver_test.ko${mod_compression_ext}" ]] ; then
    echo >&2 "Error: module not removed in /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_multiver_test.ko${mod_compression_ext}"
    exit 1
fi

echo 'Unbuilding the multiver test modules'
run_with_expected_output dkms unbuild -k "${KERNEL_VER}" -m dkms_multiver_test -v 1.0 << EOF
Module dkms_multiver_test 1.0 is not installed for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0: added
dkms_multiver_test/2.0, ${KERNEL_VER}, $(uname -m): built
EOF
run_with_expected_output dkms unbuild -k "${KERNEL_VER}" -m dkms_multiver_test -v 2.0 << EOF
Module dkms_multiver_test 2.0 is not installed for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0: added
dkms_multiver_test/2.0: added
EOF

echo 'Removing the multiver test modules'
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_multiver_test -v 1.0 << EOF
Module dkms_multiver_test 1.0 is not installed for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
Module dkms_multiver_test 1.0 is not built for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
Deleting module dkms_multiver_test-1.0 completely from the DKMS tree.
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/2.0: added
EOF
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_multiver_test -v 2.0 << EOF
Module dkms_multiver_test 2.0 is not installed for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
Module dkms_multiver_test 2.0 is not built for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
Deleting module dkms_multiver_test-2.0 completely from the DKMS tree.
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
EOF

echo 'Removing /usr/src/dkms_multiver_test-1.0 /usr/src/dkms_multiver_test-2.0'
rm -r /usr/src/dkms_multiver_test-1.0 /usr/src/dkms_multiver_test-2.0

echo 'Checking that the environment is clean'
check_no_dkms_test

echo 'Running autoinstall error testing'

echo 'Adding failing test module by directory'
run_with_expected_output dkms add test/dkms_failing_test-1.0 << EOF
Creating symlink /var/lib/dkms/dkms_failing_test/1.0/source -> /usr/src/dkms_failing_test-1.0
EOF
echo 'Running autoinstall with failing test module (expected error)'
run_with_expected_error 11 dkms autoinstall -k "${KERNEL_VER}" << EOF

Building module:
Cleaning build area...(bad exit status: 2)
make -j$(nproc) KERNELRELEASE=${KERNEL_VER} all...(bad exit status: 2)
Error! Bad return status for module build on kernel: ${KERNEL_VER} ($(uname -m))
Consult /var/lib/dkms/dkms_failing_test/1.0/build/make.log for more information.
Error! One or more modules failed to install during autoinstall.
Refer to previous errors for more information.
EOF

echo 'Adding test module with dependencies on failing test module by directory'
run_with_expected_output dkms add test/dkms_dependencies_test-1.0 << EOF
Creating symlink /var/lib/dkms/dkms_dependencies_test/1.0/source -> /usr/src/dkms_dependencies_test-1.0
EOF
echo 'Running autoinstall with failing test module and test module with dependencies on the failing module (expected error)'
run_with_expected_error 11 dkms autoinstall -k "${KERNEL_VER}" << EOF

Building module:
Cleaning build area...(bad exit status: 2)
make -j$(nproc) KERNELRELEASE=${KERNEL_VER} all...(bad exit status: 2)
Error! Bad return status for module build on kernel: ${KERNEL_VER} ($(uname -m))
Consult /var/lib/dkms/dkms_failing_test/1.0/build/make.log for more information.
dkms_dependencies_test/1.0 autoinstall failed due to missing dependencies: dkms_failing_test
Error! One or more modules failed to install during autoinstall.
Refer to previous errors for more information.
EOF

echo 'Removing failing test module'
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_failing_test -v 1.0 << EOF
Module dkms_failing_test 1.0 is not installed for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
Module dkms_failing_test 1.0 is not built for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
Deleting module dkms_failing_test-1.0 completely from the DKMS tree.
EOF
echo 'Removing /usr/src/dkms_failing_test-1.0'
rm -r /usr/src/dkms_failing_test-1.0

echo 'Running autoinstall with test module with missing dependencies (expected error)'
run_with_expected_error 11 dkms autoinstall -k "${KERNEL_VER}" << EOF
dkms_dependencies_test/1.0 autoinstall failed due to missing dependencies: dkms_failing_test
Error! One or more modules failed to install during autoinstall.
Refer to previous errors for more information.
EOF

echo 'Removing test module with dependencies'
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_dependencies_test -v 1.0 << EOF
Module dkms_dependencies_test 1.0 is not installed for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
Module dkms_dependencies_test 1.0 is not built for kernel ${KERNEL_VER} ($(uname -m)). Skipping...
Deleting module dkms_dependencies_test-1.0 completely from the DKMS tree.
EOF
echo 'Removing /usr/src/dkms_dependencies_test-1.0'
rm -r /usr/src/dkms_dependencies_test-1.0

echo 'Checking that the environment is clean again'
check_no_dkms_test

echo 'All tests successful :)'
