#!/bin/bash
# Test that dkms works properly
set -eu

# Change the to base directory
cd "$(dirname -- "$0")"

# To use a specific kernel version, use the environment variable KERNEL_VER
KERNEL_VER="${KERNEL_VER:-$(uname -r)}"
KERNEL_ARCH="$(uname -m)"
echo "Using kernel ${KERNEL_VER}/${KERNEL_ARCH}"

# debconf can trigger at random points, in the testing process. Where a bunch of
# the frontends cannot work in our CI. Just opt for the noninteractive one.
export DEBIAN_FRONTEND=noninteractive

# Avoid output variations due to parallelism
export parallel_jobs=1

# Temporary files, directories, and modules created during tests
TEST_MODULES=(
    "dkms_test"
    "dkms_noautoinstall_test"
    "dkms_failing_test"
    "dkms_dependencies_test"
    "dkms_multiver_test"
    "dkms_nover_test"
    "dkms_emptyver_test"
    "dkms_nover_update_test"
    "dkms_conf_test"
    "dkms_build_exclusive_test"
    "dkms_build_exclusive_dependencies_test"
)
TEST_TMPDIRS=(
    "/usr/src/dkms_test-1.0"
    "/usr/src/dkms_noautoinstall_test-1.0"
    "/usr/src/dkms_failing_test-1.0"
    "/usr/src/dkms_dependencies_test-1.0"
    "/usr/src/dkms_multiver_test-1.0"
    "/usr/src/dkms_multiver_test-2.0"
    "/usr/src/dkms_nover_test-1.0"
    "/usr/src/dkms_emptyver_test-1.0"
    "/usr/src/dkms_nover_update_test-1.0"
    "/usr/src/dkms_nover_update_test-2.0"
    "/usr/src/dkms_nover_update_test-3.0"
    "/usr/src/dkms_conf_test-1.0"
    "/usr/src/dkms_build_exclusive_test-1.0"
    "/usr/src/dkms_build_exclusive_dependencies_test-1.0"
    "/tmp/dkms_test_dir_${KERNEL_VER}/"
)
TEST_TMPFILES=(
    "/tmp/dkms_test_private_key"
    "/tmp/dkms_test_certificate"
    "/tmp/dkms_test_kconfig"
    "/etc/dkms/framework.conf.d/dkms_test_framework.conf"
    "test_cmd_output.log"
    "test_cmd_stdout.log"
    "test_cmd_stderr.log"
    "test_cmd_expected_output.log"
)

# Reportedly in some cases the entries in the modinfo output are ordered
# differently. Fetch whatever we need and sort them.
modinfo_quad() {
    modinfo $1 | grep -E "^description:|^filename:|^license:|^version:" | sort
}

SIGNING_MESSAGE=""
declare -i NO_SIGNING_TOOL
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
    if (( NO_SIGNING_TOOL == 0 )); then
        SIGNING_MESSAGE="Signing module /var/lib/dkms/$1/$2/build/${3:-$1}.ko"$'\n'
    fi
}

run_status_with_expected_output() {
    local module=$1

    cat > test_cmd_expected_output.log
    dkms_status_grep_dkms_module "${module}" > test_cmd_output.log 2>&1
    if ! diff -U3 test_cmd_expected_output.log test_cmd_output.log ; then
        echo >&2 "Error: unexpected output from: dkms_status_grep_dkms_module for ${module}"
        return 1
    fi
    rm test_cmd_expected_output.log test_cmd_output.log
}

generalize_expected_output() {
    local output_log=$1

    # On CentOS, weak-modules is executed. Drop it from the output, to be more generic
    sed -i '/^Adding any weak-modules$/d' ${output_log}
    sed -i '/^Removing any linked weak-modules$/d' ${output_log}
    # Signing related output. Drop it from the output, to be more generic
    if (( NO_SIGNING_TOOL == 0 )); then
        sed -i '/^EFI variables are not supported on this system/d' ${output_log}
        sed -i '/^\/sys\/firmware\/efi\/efivars not found, aborting./d' ${output_log}
        sed -i '/^Sign command:/d' ${output_log}
        sed -i '/^Signing key:/d' ${output_log}
        sed -i '/^Public certificate (MOK):/d' ${output_log}
        sed -i '/^Certificate or key are missing, generating them using update-secureboot-policy...$/d' ${output_log}
        sed -i '/^Certificate or key are missing, generating self signed certificate for MOK...$/d' ${output_log}
    else
        sed -i "/^The kernel is built without module signing facility, modules won't be signed$/d" ${output_log}
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

    # Swap any CC/LD/... flags (if set) with a placeholder message
    sed -i "s|\(make -j1 KERNELRELEASE=${KERNEL_VER} all\).*|\1 <omitting possibly set CC/LD/... flags>|" ${output_log}
}

run_with_expected_output() {
    run_with_expected_error 0 "$@"
}

run_with_expected_error() {
    local expected_error_code="$1"
    local dkms_command="$3"
    local output_log=test_cmd_output.log
    local expected_output_log=test_cmd_expected_output.log
    local error_code=0

    shift
    cat > ${expected_output_log}
    stdbuf -o L -e L "$@" > ${output_log} 2>&1 || error_code=$?
    if [[ "${error_code}" != "${expected_error_code}" ]] ; then
        echo "Error: command '$*' returned status ${error_code} instead of expected ${expected_error_code}"
        cat ${output_log}
        rm ${expected_output_log} ${output_log}
        return 1
    fi
    generalize_expected_output ${output_log} ${dkms_command}
    if ! diff -U3 ${expected_output_log} ${output_log} ; then
        echo >&2 "Error: unexpected output from: $*"
        rm ${expected_output_log} ${output_log}
        return 1
    fi
    rm ${expected_output_log} ${output_log}
}

# sig_hashalgo itself may show bogus value if kmod version < 26
kmod_broken_hashalgo() {
    local -ri kmod_ver=$(kmod --version | grep version | cut -f 3 -d ' ')

    (( kmod_ver < 26 ))
}

mod_compression_ext=
kernel_config="/lib/modules/${KERNEL_VER}/build/.config"
if [ -f "${kernel_config}" ]; then
    if grep -q "^CONFIG_MODULE_COMPRESS_NONE=y" "${kernel_config}" ; then
        mod_compression_ext=
    elif grep -q "^CONFIG_MODULE_COMPRESS_GZIP=y" "${kernel_config}" ; then
        mod_compression_ext=.gz
    elif grep -q "^CONFIG_MODULE_COMPRESS_XZ=y" "${kernel_config}" ; then
        mod_compression_ext=.xz
    elif grep -q "^CONFIG_MODULE_COMPRESS_ZSTD=y" "${kernel_config}" ; then
        mod_compression_ext=.zst
    fi
fi

# Compute the expected destination module location
os_id="$(sed -n 's/^ID\s*=\s*\(.*\)$/\1/p' /etc/os-release | tr -d '"')"
case "${os_id}" in
    centos | fedora | rhel | ovm | almalinux)
        expected_dest_loc=extra
        mod_compression_ext=.xz
        ;;
    sles | suse | opensuse*)
        expected_dest_loc=updates
        mod_compression_ext=.zst
        ;;
    arch)
        expected_dest_loc=updates/dkms
        ;;
    debian* | ubuntu | linuxmint)
        expected_dest_loc=updates/dkms
        ;;
    alpine)
        expected_dest_loc=kernel/extra
        ;;
    gentoo)
        expected_dest_loc=kernel/extra
        mod_compression_ext=
        ;;
    *)
        echo >&2 "Error: unknown Linux distribution ID ${os_id}"
        exit 1
        ;;
esac

echo "Checking module compression ..."
echo "config: $(grep "^CONFIG_MODULE_COMPRESS" "${kernel_config}" || true)"
echo "files: $(find  "/lib/modules/${KERNEL_VER}" -name \*.ko\* 2>/dev/null | head -n1)"
echo "Expected extension: ${mod_compression_ext:-(none)}"


echo 'Preparing a clean test environment'
clean_dkms_env

echo 'Test framework file hijacking'
mkdir -p /etc/dkms/framework.conf.d/
cp test/framework/hijacking.conf /etc/dkms/framework.conf.d/dkms_test_framework.conf
run_with_expected_output dkms status -m dkms_test << EOF
EOF
rm /etc/dkms/framework.conf.d/dkms_test_framework.conf

############################################################################
### Testing dkms on a regular module                                     ###
############################################################################

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
    exit 1
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

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
EOF

echo 'Building the test module again'
run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test/1.0 already built for kernel ${KERNEL_VER} (${KERNEL_ARCH}), skip. You may override by specifying --force.
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
EOF

if (( NO_SIGNING_TOOL == 0 )); then
    echo 'Building the test module with bad sign_file path in framework file'
    cp test/framework/bad_sign_file_path.conf /etc/dkms/framework.conf.d/dkms_test_framework.conf
    run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 --force << EOF
Binary /no/such/file not found, modules won't be signed

Cleaning build area... done.
Building module(s)... done.
Cleaning build area... done.
EOF

    echo ' Building the test module with bad mok_signing_key path in framework file'
    cp test/framework/bad_key_file_path.conf /etc/dkms/framework.conf.d/dkms_test_framework.conf
    run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 --force << EOF
Key file /no/such/path.key not found and can't be generated, modules won't be signed

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.
EOF

    echo ' Building the test module with bad mok_certificate path in framework file'
    cp test/framework/bad_cert_file_path.conf /etc/dkms/framework.conf.d/dkms_test_framework.conf
    run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 --force << EOF
Certificate file /no/such/path.crt not found and can't be generated, modules won't be signed

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.
EOF
    rm /tmp/dkms_test_private_key

    echo ' Building the test module with path contains variables in framework file'
    mkdir "/tmp/dkms_test_dir_${KERNEL_VER}/"
    cp test/framework/variables_in_path.conf /etc/dkms/framework.conf.d/dkms_test_framework.conf
    run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 --force << EOF

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.
EOF
    rm -r "/tmp/dkms_test_dir_${KERNEL_VER}/"

    BUILT_MODULE_PATH="/var/lib/dkms/dkms_test/1.0/${KERNEL_VER}/${KERNEL_ARCH}/module/dkms_test.ko${mod_compression_ext}"
    CURRENT_HASH="$(modinfo -F sig_hashalgo "${BUILT_MODULE_PATH}")"

    echo ' Building the test module using a different hash algorithm'
    if kmod_broken_hashalgo; then
        echo '  Current kmod has broken hash algorithm code. Skipping...'
    elif [[ "${CURRENT_HASH}" == "unknown" ]]; then
        echo '  Current kmod reports unknown hash algorithm. Skipping...'
    else
        cp test/framework/temp_key_cert.conf /etc/dkms/framework.conf.d/dkms_test_framework.conf

        if [[ "${CURRENT_HASH}" == "sha512" ]]; then
            ALTER_HASH="sha256"
        else
            ALTER_HASH="sha512"
        fi
        echo "CONFIG_MODULE_SIG_HASH=\"${ALTER_HASH}\"" > /tmp/dkms_test_kconfig
        run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 --config /tmp/dkms_test_kconfig --force << EOF

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.
EOF
        run_with_expected_output sh -c "modinfo -F sig_hashalgo '${BUILT_MODULE_PATH}'" << EOF
${ALTER_HASH}
EOF
        rm /tmp/dkms_test_kconfig
    fi

    rm /etc/dkms/framework.conf.d/dkms_test_framework.conf
fi

cp test/framework/temp_key_cert.conf /etc/dkms/framework.conf.d/dkms_test_framework.conf

echo 'Building the test module again by force'
run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_test -v 1.0 --force << EOF

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
EOF

if (( NO_SIGNING_TOOL == 0 )); then
    echo ' Extracting serial number from the certificate'
    MODULE_SERIAL="$(cert_serial /tmp/dkms_test_certificate)"
fi

echo 'Installing the test module'
run_with_expected_output dkms install -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF

Installing /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}

Running depmod... done.
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
EOF

echo 'Installing the test module again'
run_with_expected_output dkms install -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test/1.0 already installed on kernel ${KERNEL_VER} (${KERNEL_ARCH}), skip. You may override by specifying --force.
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
EOF
if ! [[ -f "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}" ]] ; then
    echo >&2 "Error: module not found in /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}"
    exit 1
fi

echo 'Installing the test module again by force'
run_with_expected_output dkms install -k "${KERNEL_VER}" -m dkms_test -v 1.0 --force << EOF
Module dkms_test-1.0 for kernel ${KERNEL_VER} (${KERNEL_ARCH}).
Before uninstall, this module version was ACTIVE on this kernel.

Deleting /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}

Running depmod... done.

Installing /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}

Running depmod... done.
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
EOF

echo 'Checking modinfo'
run_with_expected_output sh -c "$(declare -f modinfo_quad); modinfo_quad /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}" << EOF
description:    A Simple dkms test module
filename:       /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}
license:        GPL
version:        1.0
EOF

if (( NO_SIGNING_TOOL == 0 )); then
    echo ' Checking module signature'
    SIG_KEY="$(modinfo -F sig_key "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}" | tr -d ':')"
    SIG_HASH="$(modinfo -F sig_hashalgo "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}")"

    if kmod_broken_hashalgo; then
        echo '  Current kmod has broken hash algorithm code. Skipping...'
    elif [[ "${SIG_HASH}" == "unknown" ]]; then
        echo '  Current kmod reports unknown hash algorithm. Skipping...'
    elif [[ ! "${SIG_KEY}" ]]; then
        echo >&2 "Error: module was not signed"
        exit 1
    else
        run_with_expected_output sh -c "echo '${SIG_KEY}'" << EOF
${MODULE_SERIAL}
EOF
    fi
fi

echo 'Uninstalling the test module'
run_with_expected_output dkms uninstall -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test-1.0 for kernel ${KERNEL_VER} (${KERNEL_ARCH}).
Before uninstall, this module version was ACTIVE on this kernel.

Deleting /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}

Running depmod... done.
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
EOF
if [[ -e "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}" ]] ; then
    echo >&2 "Error: module not removed in /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}"
    exit 1
fi

echo 'Uninstalling the test module again'
run_with_expected_output dkms uninstall -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
EOF

echo 'Unbuilding the test module'
run_with_expected_output dkms unbuild -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0: added
EOF

echo 'Unbuilding the test module again'
run_with_expected_output dkms unbuild -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Module dkms_test 1.0 is not built for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0: added
EOF

echo 'Removing the test module'
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Module dkms_test 1.0 is not built for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Deleting module dkms_test-1.0 completely from the DKMS tree.
EOF
run_status_with_expected_output 'dkms_test' << EOF
EOF
if ! [[ -d /usr/src/dkms_test-1.0 ]] ; then
    echo >&2 'Error: directory /usr/src/dkms_test-1.0 was removed'
    exit 1
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

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.

Installing /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}

Running depmod... done.
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
EOF
if ! [[ -f "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}" ]] ; then
    echo >&2 "Error: module not found in /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}"
    exit 1
fi

echo 'Checking modinfo'
run_with_expected_output sh -c "$(declare -f modinfo_quad); modinfo_quad /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}" << EOF
description:    A Simple dkms test module
filename:       /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}
license:        GPL
version:        1.0
EOF

if (( NO_SIGNING_TOOL == 0 )); then
    echo ' Checking module signature'
    SIG_KEY="$(modinfo -F sig_key "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}" | tr -d ':')"
    SIG_HASH="$(modinfo -F sig_hashalgo "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}")"

    if kmod_broken_hashalgo; then
        echo '  Current kmod has broken hash algorithm code. Skipping...'
    elif [[ "${SIG_HASH}" == "unknown" ]]; then
        echo '  Current kmod reports unknown hash algorithm. Skipping...'
    elif [[ ! "${SIG_KEY}" ]]; then
        # kmod may not be linked with openssl and thus can't extract the key from module
        echo >&2 "Error: modules was not signed, or key is unknown"
        exit 1
    else
        run_with_expected_output sh -c "echo '${SIG_KEY}'" << EOF
${MODULE_SERIAL}
EOF
    fi
fi

echo 'Removing the test module with --all'
run_with_expected_output dkms remove --all -m dkms_test -v 1.0 << EOF
Module dkms_test-1.0 for kernel ${KERNEL_VER} (${KERNEL_ARCH}).
Before uninstall, this module version was ACTIVE on this kernel.

Deleting /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}

Running depmod... done.
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

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
EOF

echo "Running dkms autoinstall"
run_with_expected_output dkms autoinstall -k "${KERNEL_VER}" << EOF

Installing /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}

Running depmod... done.
dkms autoinstall on ${KERNEL_VER}/${KERNEL_ARCH} succeeded for dkms_test
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
EOF

echo "Running dkms autoinstall for a kernel without headers installed (expected error)"
run_with_expected_error 11 dkms autoinstall -k "${KERNEL_VER}-noheaders" << EOF

Error! Your kernel headers for kernel ${KERNEL_VER}-noheaders cannot be found at /lib/modules/${KERNEL_VER}-noheaders/build or /lib/modules/${KERNEL_VER}-noheaders/source.
Please install the linux-headers-${KERNEL_VER}-noheaders package or use the --kernelsourcedir option to tell DKMS where it's located.
dkms autoinstall on ${KERNEL_VER}-noheaders/${KERNEL_ARCH} failed for dkms_test(1)

Error! One or more modules failed to install during autoinstall.
Refer to previous errors for more information.
EOF

echo 'Removing the test module with --all'
run_with_expected_output dkms remove --all -m dkms_test -v 1.0 << EOF
Module dkms_test-1.0 for kernel ${KERNEL_VER} (${KERNEL_ARCH}).
Before uninstall, this module version was ACTIVE on this kernel.

Deleting /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}

Running depmod... done.
Deleting module dkms_test-1.0 completely from the DKMS tree.
EOF
run_status_with_expected_output 'dkms_test' << EOF
EOF

echo 'Removing temporary files'
if (( NO_SIGNING_TOOL == 0 )); then
    rm /tmp/dkms_test_private_key /tmp/dkms_test_certificate
fi
rm /etc/dkms/framework.conf.d/dkms_test_framework.conf

echo 'Removing /usr/src/dkms_test-1.0'
rm -r /usr/src/dkms_test-1.0

echo 'Checking that the environment is clean again'
check_no_dkms_test

############################################################################
### Testing dkms on a regular module with AUTOINSTALL=""                 ###
############################################################################

echo 'Adding the noautoinstall test module by directory'
run_with_expected_output dkms add test/dkms_noautoinstall_test-1.0 << EOF
Creating symlink /var/lib/dkms/dkms_noautoinstall_test/1.0/source -> /usr/src/dkms_noautoinstall_test-1.0
EOF
run_status_with_expected_output 'dkms_noautoinstall_test' << EOF
dkms_noautoinstall_test/1.0: added
EOF
if ! [[ -d /usr/src/dkms_noautoinstall_test-1.0 ]] ; then
    echo >&2 'Error: directory /usr/src/dkms_noautoinstall_test-1.0 was not created'
    exit 1
fi

echo "Running dkms autoinstall"
run_with_expected_output dkms autoinstall -k "${KERNEL_VER}" << EOF
EOF
run_status_with_expected_output 'dkms_noautoinstall_test' << EOF
dkms_noautoinstall_test/1.0: added
EOF

echo 'Building the noautoinstall test module'
set_signing_message "dkms_noautoinstall_test" "1.0"
run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_noautoinstall_test -v 1.0 << EOF

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.
EOF
run_status_with_expected_output 'dkms_noautoinstall_test' << EOF
dkms_noautoinstall_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
EOF

echo 'Installing the noautoinstall test module'
run_with_expected_output dkms install -k "${KERNEL_VER}" -m dkms_noautoinstall_test -v 1.0 << EOF

Installing /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_noautoinstall_test.ko${mod_compression_ext}

Running depmod... done.
EOF
run_status_with_expected_output 'dkms_noautoinstall_test' << EOF
dkms_noautoinstall_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
EOF

echo 'Uninstalling the noautoinstall test module'
run_with_expected_output dkms uninstall -k "${KERNEL_VER}" -m dkms_noautoinstall_test -v 1.0 << EOF
Module dkms_noautoinstall_test-1.0 for kernel ${KERNEL_VER} (${KERNEL_ARCH}).
Before uninstall, this module version was ACTIVE on this kernel.

Deleting /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_noautoinstall_test.ko${mod_compression_ext}

Running depmod... done.
EOF
run_status_with_expected_output 'dkms_noautoinstall_test' << EOF
dkms_noautoinstall_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
EOF
if [[ -e "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_noautoinstall_test.ko${mod_compression_ext}" ]] ; then
    echo >&2 "Error: module not removed in /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_noautoinstall_test.ko${mod_compression_ext}"
    exit 1
fi

echo 'Unbuilding the noautoinstall test module'
run_with_expected_output dkms unbuild -k "${KERNEL_VER}" -m dkms_noautoinstall_test -v 1.0 << EOF
Module dkms_noautoinstall_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
EOF
run_status_with_expected_output 'dkms_noautoinstall_test' << EOF
dkms_noautoinstall_test/1.0: added
EOF

echo 'Removing the noautoinstall test module'
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_noautoinstall_test -v 1.0 << EOF
Module dkms_noautoinstall_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Module dkms_noautoinstall_test 1.0 is not built for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Deleting module dkms_noautoinstall_test-1.0 completely from the DKMS tree.
EOF
run_status_with_expected_output 'dkms_noautoinstall_test' << EOF
EOF
if ! [[ -d /usr/src/dkms_noautoinstall_test-1.0 ]] ; then
    echo >&2 'Error: directory /usr/src/dkms_noautoinstall_test-1.0 was removed'
    exit 1
fi

echo 'Removing /usr/src/dkms_noautoinstall_test-1.0'
rm -r /usr/src/dkms_noautoinstall_test-1.0

echo 'Checking that the environment is clean again'
check_no_dkms_test

############################################################################
### Testing malformed/borderline dkms.conf                               ###
############################################################################

abspwd=$(readlink -f $(pwd))

echo 'Testing dkms add of source tree without dkms.conf (expected error)'
run_with_expected_error 1 dkms add ${abspwd}/test/dkms_conf_test_no_conf << EOF

Error! Arguments <module> and <module-version> are not specified.
Usage: add <module>/<module-version> or
       add -m <module>/<module-version> or
       add -m <module> -v <module-version>
EOF

echo 'Testing dkms add with empty dkms.conf (expected error)'
run_with_expected_error 8 dkms add test/dkms_conf_test_empty << EOF
dkms.conf: Error! No 'PACKAGE_NAME' directive specified.
dkms.conf: Error! No 'PACKAGE_VERSION' directive specified.
dkms.conf: Warning! Zero modules specified.

Error! Bad conf file.
File: ${abspwd}/test/dkms_conf_test_empty/dkms.conf does not represent a valid dkms.conf file.
EOF

echo 'Testing dkms.conf with invalid values (expected error)'
run_with_expected_error 8 dkms add test/dkms_conf_test_invalid << EOF
dkms.conf: Error! No 'BUILT_MODULE_NAME' directive specified for record #0.
dkms.conf: Error! 'DEST_MODULE_NAME' directive ends in '.o' or '.ko' in record #0.
dkms.conf: Error! Directive 'DEST_MODULE_LOCATION' does not begin with
'/kernel', '/updates', or '/extra' in record #0.
dkms.conf: Error! 'BUILT_MODULE_NAME' directive ends in '.o' or '.ko' in record #1.
dkms.conf: Error! No 'DEST_MODULE_LOCATION' directive specified for record #1.
dkms.conf: Error! Directive 'DEST_MODULE_LOCATION' does not begin with
'/kernel', '/updates', or '/extra' in record #1.

Error! Bad conf file.
File: ${abspwd}/test/dkms_conf_test_invalid/dkms.conf does not represent a valid dkms.conf file.
EOF

echo 'Testing dkms.conf defining zero modules'
run_with_expected_output dkms add test/dkms_conf_test_zero_modules << EOF
dkms.conf: Warning! Zero modules specified.
dkms.conf: Warning! Zero modules specified.
Creating symlink /var/lib/dkms/dkms_conf_test/1.0/source -> /usr/src/dkms_conf_test-1.0
EOF
run_status_with_expected_output 'dkms_conf_test' << EOF
dkms_conf_test/1.0: added
EOF

run_with_expected_output dkms remove --all -m dkms_conf_test -v 1.0 << EOF
Deleting module dkms_conf_test-1.0 completely from the DKMS tree.
EOF
run_status_with_expected_output 'dkms_conf_test' << EOF
EOF

echo 'Testing add/build/install of a test module building zero kernel modules'
run_with_expected_output dkms install -k "${KERNEL_VER}" -m dkms_conf_test -v 1.0 << EOF
dkms.conf: Warning! Zero modules specified.
Creating symlink /var/lib/dkms/dkms_conf_test/1.0/source -> /usr/src/dkms_conf_test-1.0

Cleaning build area... done.
Building module(s)... done.
Cleaning build area... done.


Running depmod... done.
EOF
run_status_with_expected_output 'dkms_conf_test' << EOF
dkms.conf: Warning! Zero modules specified.
dkms_conf_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
EOF

run_with_expected_output dkms remove --all -m dkms_conf_test -v 1.0 << EOF
dkms.conf: Warning! Zero modules specified.
dkms.conf: Warning! Zero modules specified.
Module dkms_conf_test-1.0 for kernel ${KERNEL_VER} (${KERNEL_ARCH}).
Before uninstall, this module version was ACTIVE on this kernel.


Running depmod... done.
Deleting module dkms_conf_test-1.0 completely from the DKMS tree.
EOF

echo 'Removing /usr/src/dkms_conf_test-1.0'
rm -r /usr/src/dkms_conf_test-1.0

echo 'Testing dkms.conf with defaulted BUILT_MODULE_NAME'
run_with_expected_output dkms add test/dkms_conf_test_defaulted_BUILT_MODULE_NAME << EOF
Creating symlink /var/lib/dkms/dkms_conf_test/1.0/source -> /usr/src/dkms_conf_test-1.0
EOF

echo 'Building test module without source (expected error)'
run_with_expected_error 8 dkms build -k "${KERNEL_VER}" -m dkms_conf_test -v 1.0 << EOF

Error! The directory /var/lib/dkms/dkms_conf_test/1.0/source does not appear to have module source located within it.
Build halted.
EOF
run_status_with_expected_output 'dkms_conf_test' << EOF
dkms_conf_test/1.0: added
EOF

run_with_expected_output dkms remove --all -m dkms_conf_test -v 1.0 << EOF
Deleting module dkms_conf_test-1.0 completely from the DKMS tree.
EOF

echo 'Removing /usr/src/dkms_conf_test-1.0'
rm -r /usr/src/dkms_conf_test-1.0

echo 'Checking that the environment is clean again'
check_no_dkms_test

############################################################################
### Testing dkms on a module with multiple versions                      ###
############################################################################

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

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
dkms_multiver_test/2.0: added
EOF
set_signing_message "dkms_multiver_test" "2.0"
run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_multiver_test -v 2.0 << EOF

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
dkms_multiver_test/2.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
EOF

echo 'Installing the multiver test modules'
run_with_expected_output dkms install -k "${KERNEL_VER}" -m dkms_multiver_test -v 1.0 << EOF

Installing /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_multiver_test.ko${mod_compression_ext}

Running depmod... done.
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
dkms_multiver_test/2.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
EOF
run_with_expected_output dkms install -k "${KERNEL_VER}" -m dkms_multiver_test -v 2.0 << EOF

Installing /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_multiver_test.ko${mod_compression_ext}

Running depmod... done.
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
dkms_multiver_test/2.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
EOF
run_with_expected_error 6 dkms install -k "${KERNEL_VER}" -m dkms_multiver_test -v 1.0 << EOF


Error! Module version 1.0 for dkms_multiver_test.ko${mod_compression_ext}
is not newer than what is already found in kernel ${KERNEL_VER} (2.0).
You may override by specifying --force.


Error! Installation aborted.
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
dkms_multiver_test/2.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
EOF

echo 'Uninstalling the multiver test modules'
run_with_expected_output dkms uninstall -k "${KERNEL_VER}" -m dkms_multiver_test -v 1.0 << EOF
Module dkms_multiver_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
dkms_multiver_test/2.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
EOF
run_with_expected_output dkms uninstall -k "${KERNEL_VER}" -m dkms_multiver_test -v 2.0 << EOF
Module dkms_multiver_test-2.0 for kernel ${KERNEL_VER} (${KERNEL_ARCH}).
Before uninstall, this module version was ACTIVE on this kernel.

Deleting /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_multiver_test.ko${mod_compression_ext}

Running depmod... done.
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
dkms_multiver_test/2.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
EOF
if [[ -e "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_multiver_test.ko${mod_compression_ext}" ]] ; then
    echo >&2 "Error: module not removed in /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_multiver_test.ko${mod_compression_ext}"
    exit 1
fi

echo 'Unbuilding the multiver test modules'
run_with_expected_output dkms unbuild -k "${KERNEL_VER}" -m dkms_multiver_test -v 1.0 << EOF
Module dkms_multiver_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0: added
dkms_multiver_test/2.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
EOF
run_with_expected_output dkms unbuild -k "${KERNEL_VER}" -m dkms_multiver_test -v 2.0 << EOF
Module dkms_multiver_test 2.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/1.0: added
dkms_multiver_test/2.0: added
EOF

echo 'Removing the multiver test modules'
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_multiver_test -v 1.0 << EOF
Module dkms_multiver_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Module dkms_multiver_test 1.0 is not built for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Deleting module dkms_multiver_test-1.0 completely from the DKMS tree.
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
dkms_multiver_test/2.0: added
EOF
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_multiver_test -v 2.0 << EOF
Module dkms_multiver_test 2.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Module dkms_multiver_test 2.0 is not built for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Deleting module dkms_multiver_test-2.0 completely from the DKMS tree.
EOF
run_status_with_expected_output 'dkms_multiver_test' << EOF
EOF

echo 'Removing /usr/src/dkms_multiver_test-1.0 /usr/src/dkms_multiver_test-2.0'
rm -r /usr/src/dkms_multiver_test-1.0 /usr/src/dkms_multiver_test-2.0

echo 'Checking that the environment is clean again'
check_no_dkms_test

############################################################################
### Testing dkms operations ...
############################################################################

echo 'Adding the nover/emptyver test modules by directory'
run_with_expected_output dkms add test/dkms_nover_test << EOF
Creating symlink /var/lib/dkms/dkms_nover_test/1.0/source -> /usr/src/dkms_nover_test-1.0
EOF
run_status_with_expected_output 'dkms_nover_test' << EOF
dkms_nover_test/1.0: added
EOF
if ! [[ -d /usr/src/dkms_nover_test-1.0 ]] ; then
    echo >&2 'Error: directory /usr/src/dkms_nover_test-1.0 was not created'
    exit 1
fi
run_with_expected_output dkms add test/dkms_emptyver_test << EOF
Creating symlink /var/lib/dkms/dkms_emptyver_test/1.0/source -> /usr/src/dkms_emptyver_test-1.0
EOF
run_status_with_expected_output 'dkms_emptyver_test' << EOF
dkms_emptyver_test/1.0: added
EOF
if ! [[ -d /usr/src/dkms_emptyver_test-1.0 ]] ; then
    echo >&2 'Error: directory /usr/src/dkms_emptyver_test-1.0 was not created'
    exit 1
fi

echo 'Building the nover/emptyver test modules'
set_signing_message "dkms_nover_test" "1.0"
run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_nover_test -v 1.0 << EOF

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.
EOF
run_status_with_expected_output 'dkms_nover_test' << EOF
dkms_nover_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
EOF
set_signing_message "dkms_emptyver_test" "1.0"
run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_emptyver_test -v 1.0 << EOF

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.
EOF
run_status_with_expected_output 'dkms_emptyver_test' << EOF
dkms_emptyver_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
EOF

echo 'Installing the nover/emptyver test modules'
run_with_expected_output dkms install -k "${KERNEL_VER}" -m dkms_nover_test -v 1.0 << EOF

Installing /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_nover_test.ko${mod_compression_ext}

Running depmod... done.
EOF
run_status_with_expected_output 'dkms_nover_test' << EOF
dkms_nover_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
EOF
run_with_expected_output dkms install -k "${KERNEL_VER}" -m dkms_emptyver_test -v 1.0 << EOF

Installing /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_emptyver_test.ko${mod_compression_ext}

Running depmod... done.
EOF
run_status_with_expected_output 'dkms_emptyver_test' << EOF
dkms_emptyver_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
EOF

echo 'Uninstalling the nover/emptyver test modules'
run_with_expected_output dkms uninstall -k "${KERNEL_VER}" -m dkms_nover_test -v 1.0 << EOF
Module dkms_nover_test-1.0 for kernel ${KERNEL_VER} (${KERNEL_ARCH}).
Before uninstall, this module version was ACTIVE on this kernel.

Deleting /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_nover_test.ko${mod_compression_ext}

Running depmod... done.
EOF
run_status_with_expected_output 'dkms_nover_test' << EOF
dkms_nover_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
EOF
if [[ -e "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_nover_test.ko${mod_compression_ext}" ]] ; then
    echo >&2 "Error: module not removed in /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_nover_test.ko${mod_compression_ext}"
    exit 1
fi
run_with_expected_output dkms uninstall -k "${KERNEL_VER}" -m dkms_emptyver_test -v 1.0 << EOF
Module dkms_emptyver_test-1.0 for kernel ${KERNEL_VER} (${KERNEL_ARCH}).
Before uninstall, this module version was ACTIVE on this kernel.

Deleting /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_emptyver_test.ko${mod_compression_ext}

Running depmod... done.
EOF
run_status_with_expected_output 'dkms_emptyver_test' << EOF
dkms_emptyver_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
EOF
if [[ -e "/lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_emptyver_test.ko${mod_compression_ext}" ]] ; then
    echo >&2 "Error: module not removed in /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_emptyver_test.ko${mod_compression_ext}"
    exit 1
fi

echo 'Unbuilding the nover/emptyver test modules'
run_with_expected_output dkms unbuild -k "${KERNEL_VER}" -m dkms_nover_test -v 1.0 << EOF
Module dkms_nover_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
EOF
run_status_with_expected_output 'dkms_nover_test' << EOF
dkms_nover_test/1.0: added
EOF
run_with_expected_output dkms unbuild -k "${KERNEL_VER}" -m dkms_emptyver_test -v 1.0 << EOF
Module dkms_emptyver_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
EOF
run_status_with_expected_output 'dkms_emptyver_test' << EOF
dkms_emptyver_test/1.0: added
EOF

echo 'Removing the nover/emptyver test modules'
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_nover_test -v 1.0 << EOF
Module dkms_nover_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Module dkms_nover_test 1.0 is not built for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Deleting module dkms_nover_test-1.0 completely from the DKMS tree.
EOF
run_status_with_expected_output 'dkms_nover_test' << EOF
EOF
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_emptyver_test -v 1.0 << EOF
Module dkms_emptyver_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Module dkms_emptyver_test 1.0 is not built for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Deleting module dkms_emptyver_test-1.0 completely from the DKMS tree.
EOF
run_status_with_expected_output 'dkms_emptyver_test' << EOF
EOF

echo 'Removing /usr/src/dkms_nover_test-1.0 /usr/src/dkms_emptyver_test-1.0'
rm -r /usr/src/dkms_nover_test-1.0 /usr/src/dkms_emptyver_test-1.0


echo 'Adding the nover update test modules 1.0 by directory'
run_with_expected_output dkms add test/dkms_nover_update_test/1.0 << EOF
Creating symlink /var/lib/dkms/dkms_nover_update_test/1.0/source -> /usr/src/dkms_nover_update_test-1.0
EOF
run_status_with_expected_output 'dkms_nover_update_test' << EOF
dkms_nover_update_test/1.0: added
EOF
if ! [[ -d /usr/src/dkms_nover_update_test-1.0 ]] ; then
    echo >&2 'Error: directory /usr/src/dkms_nover_update_test-1.0 was not created'
    exit 1
fi

echo 'Installing the nover update test 1.0 modules'
set_signing_message "dkms_nover_update_test" "1.0"
run_with_expected_output dkms install -k "${KERNEL_VER}" -m dkms_nover_update_test -v 1.0 << EOF

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.

Installing /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_nover_update_test.ko${mod_compression_ext}

Running depmod... done.
EOF
run_status_with_expected_output 'dkms_nover_update_test' << EOF
dkms_nover_update_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
EOF

echo 'Adding the nover update test modules 2.0 by directory'
run_with_expected_output dkms add test/dkms_nover_update_test/2.0 << EOF
Creating symlink /var/lib/dkms/dkms_nover_update_test/2.0/source -> /usr/src/dkms_nover_update_test-2.0
EOF
run_status_with_expected_output 'dkms_nover_update_test' << EOF
dkms_nover_update_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
dkms_nover_update_test/2.0: added
EOF
if ! [[ -d /usr/src/dkms_nover_update_test-2.0 ]] ; then
    echo >&2 'Error: directory /usr/src/dkms_nover_update_test-2.0 was not created'
    exit 1
fi

echo 'Installing the nover update test 2.0 modules'
set_signing_message "dkms_nover_update_test" "2.0"
run_with_expected_output dkms install -k "${KERNEL_VER}" -m dkms_nover_update_test -v 2.0 << EOF

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.

Installing /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_nover_update_test.ko${mod_compression_ext}

Running depmod... done.
EOF
run_status_with_expected_output 'dkms_nover_update_test' << EOF
dkms_nover_update_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
dkms_nover_update_test/2.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
EOF

echo 'Adding the nover update test modules 3.0 by directory'
run_with_expected_output dkms add test/dkms_nover_update_test/3.0 << EOF
Creating symlink /var/lib/dkms/dkms_nover_update_test/3.0/source -> /usr/src/dkms_nover_update_test-3.0
EOF
run_status_with_expected_output 'dkms_nover_update_test' << EOF
dkms_nover_update_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
dkms_nover_update_test/2.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
dkms_nover_update_test/3.0: added
EOF
if ! [[ -d /usr/src/dkms_nover_update_test-3.0 ]] ; then
    echo >&2 'Error: directory /usr/src/dkms_nover_update_test-3.0 was not created'
    exit 1
fi

echo 'Building the nover update test 3.0 modules'
set_signing_message "dkms_nover_update_test" "3.0"
run_with_expected_output dkms build -k "${KERNEL_VER}" -m dkms_nover_update_test -v 3.0 << EOF

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.
EOF
run_status_with_expected_output 'dkms_nover_update_test' << EOF
dkms_nover_update_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
dkms_nover_update_test/2.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
dkms_nover_update_test/3.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
EOF

MODULE_PATH_2="/var/lib/dkms/dkms_nover_update_test/2.0/${KERNEL_VER}/${KERNEL_ARCH}/module/dkms_nover_update_test.ko${mod_compression_ext}"
MODULE_PATH_3="/var/lib/dkms/dkms_nover_update_test/3.0/${KERNEL_VER}/${KERNEL_ARCH}/module/dkms_nover_update_test.ko${mod_compression_ext}"
if ! modinfo "${MODULE_PATH_3}" | grep -q '^srcversion:' && ! diff "${MODULE_PATH_2}" "${MODULE_PATH_3}" &>/dev/null; then
    # On debian, no srcversion in modinfo's output, the installation will always succeed
    echo ' Notice: Skip installation test on this platform'
else
    echo ' Installing the nover update test 3.0 modules (expected error)'
    set_signing_message "dkms_nover_update_test" "3.0"
    run_with_expected_error 6 dkms install -k "${KERNEL_VER}" -m dkms_nover_update_test -v 3.0 << EOF

Module /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_nover_update_test.ko${mod_compression_ext} already installed at version , override by specifying --force


Error! Installation aborted.
EOF
    run_status_with_expected_output 'dkms_nover_update_test' << EOF
dkms_nover_update_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
dkms_nover_update_test/2.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
dkms_nover_update_test/3.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
EOF
fi

echo 'Removing the nover update test modules'
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_nover_update_test -v 3.0 << EOF
Module dkms_nover_update_test 3.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Deleting module dkms_nover_update_test-3.0 completely from the DKMS tree.
EOF
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_nover_update_test -v 2.0 << EOF
Module dkms_nover_update_test-2.0 for kernel ${KERNEL_VER} (${KERNEL_ARCH}).
Before uninstall, this module version was ACTIVE on this kernel.

Deleting /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_nover_update_test.ko${mod_compression_ext}

Running depmod... done.
Deleting module dkms_nover_update_test-2.0 completely from the DKMS tree.
EOF
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_nover_update_test -v 1.0 << EOF
Module dkms_nover_update_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Deleting module dkms_nover_update_test-1.0 completely from the DKMS tree.
EOF
run_status_with_expected_output 'dkms_nover_update_test' << EOF
EOF

echo 'Removing /usr/src/dkms_nover_update_test-{1,2,3}.0'
rm -r /usr/src/dkms_nover_update_test-{1,2,3}.0

echo 'Checking that the environment is clean'
check_no_dkms_test

############################################################################
### Testing dkms autoinstall                                             ###
############################################################################

echo 'Running autoinstall error testing'

echo 'Adding failing test module by directory'
run_with_expected_output dkms add test/dkms_failing_test-1.0 << EOF
Creating symlink /var/lib/dkms/dkms_failing_test/1.0/source -> /usr/src/dkms_failing_test-1.0
EOF
echo 'Running autoinstall with failing test module (expected error)'
run_with_expected_error 11 dkms autoinstall -k "${KERNEL_VER}" << EOF

Cleaning build area... done.
Building module(s)...(bad exit status: 2)
Failed command:
make -j1 KERNELRELEASE=${KERNEL_VER} all <omitting possibly set CC/LD/... flags>
Error! Bad return status for module build on kernel: ${KERNEL_VER} (${KERNEL_ARCH})
Consult /var/lib/dkms/dkms_failing_test/1.0/build/make.log for more information.
dkms autoinstall on ${KERNEL_VER}/${KERNEL_ARCH} failed for dkms_failing_test(10)

Error! One or more modules failed to install during autoinstall.
Refer to previous errors for more information.
EOF

echo 'Adding test module with dependencies on failing test module by directory'
run_with_expected_output dkms add test/dkms_dependencies_test-1.0 << EOF
Creating symlink /var/lib/dkms/dkms_dependencies_test/1.0/source -> /usr/src/dkms_dependencies_test-1.0
EOF
echo 'Running autoinstall with failing test module and test module with dependencies on the failing module (expected error)'
run_with_expected_error 11 dkms autoinstall -k "${KERNEL_VER}" << EOF

Cleaning build area... done.
Building module(s)...(bad exit status: 2)
Failed command:
make -j1 KERNELRELEASE=${KERNEL_VER} all <omitting possibly set CC/LD/... flags>
Error! Bad return status for module build on kernel: ${KERNEL_VER} (${KERNEL_ARCH})
Consult /var/lib/dkms/dkms_failing_test/1.0/build/make.log for more information.
dkms autoinstall on ${KERNEL_VER}/${KERNEL_ARCH} failed for dkms_failing_test(10)
dkms_dependencies_test/1.0 autoinstall failed due to missing dependencies: dkms_failing_test

Error! One or more modules failed to install during autoinstall.
Refer to previous errors for more information.
EOF

echo 'Removing failing test module'
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_failing_test -v 1.0 << EOF
Module dkms_failing_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Module dkms_failing_test 1.0 is not built for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
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
Module dkms_dependencies_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Module dkms_dependencies_test 1.0 is not built for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Deleting module dkms_dependencies_test-1.0 completely from the DKMS tree.
EOF
echo 'Removing /usr/src/dkms_dependencies_test-1.0'
rm -r /usr/src/dkms_dependencies_test-1.0

echo 'Checking that the environment is clean again'
check_no_dkms_test

############################################################################
### Testing BUILD_EXCLUSIVE_*                                            ###
############################################################################

echo 'Running tests with BUILD_EXCLUSIVE_* modules'
set_signing_message "dkms_test" "1.0"

echo 'Adding the build-exclusive test module by directory'
run_with_expected_output dkms add test/dkms_build_exclusive_test-1.0 << EOF
Creating symlink /var/lib/dkms/dkms_build_exclusive_test/1.0/source -> /usr/src/dkms_build_exclusive_test-1.0
EOF
run_status_with_expected_output 'dkms_build_exclusive_test' << EOF
dkms_build_exclusive_test/1.0: added
EOF
if ! [[ -d /usr/src/dkms_build_exclusive_test-1.0 ]] ; then
    echo >&2 'Error: directory /usr/src/dkms_build_exclusive_test-1.0 was not created'
    return 1
fi

# Should this really fail?
echo '(Not) building the build-exclusive test module'
run_with_expected_error 77 dkms build -k "${KERNEL_VER}" -m dkms_build_exclusive_test -v 1.0 << EOF
Warning: The /var/lib/dkms/dkms_build_exclusive_test/1.0/${KERNEL_VER}/${KERNEL_ARCH}/dkms.conf
for module dkms_build_exclusive_test includes a BUILD_EXCLUSIVE directive
which does not match this kernel/arch/config.
This indicates that it should not be built.
EOF
run_status_with_expected_output 'dkms_build_exclusive_test' << EOF
dkms_build_exclusive_test/1.0: added
EOF

echo "Running dkms autoinstall (1 x skip)"
run_with_expected_output dkms autoinstall -k "${KERNEL_VER}" << EOF
Warning: The /var/lib/dkms/dkms_build_exclusive_test/1.0/${KERNEL_VER}/${KERNEL_ARCH}/dkms.conf
for module dkms_build_exclusive_test includes a BUILD_EXCLUSIVE directive
which does not match this kernel/arch/config.
This indicates that it should not be built.
dkms autoinstall on ${KERNEL_VER}/${KERNEL_ARCH} was skipped for dkms_build_exclusive_test
EOF
run_status_with_expected_output 'dkms_build_exclusive_test' << EOF
dkms_build_exclusive_test/1.0: added
EOF

echo 'Adding the test module by directory'
run_with_expected_output dkms add test/dkms_test-1.0 << EOF
Creating symlink /var/lib/dkms/dkms_test/1.0/source -> /usr/src/dkms_test-1.0
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0: added
EOF

echo "Running dkms autoinstall (1 x skip, 1 x pass)"
run_with_expected_output dkms autoinstall -k "${KERNEL_VER}" << EOF
Warning: The /var/lib/dkms/dkms_build_exclusive_test/1.0/${KERNEL_VER}/${KERNEL_ARCH}/dkms.conf
for module dkms_build_exclusive_test includes a BUILD_EXCLUSIVE directive
which does not match this kernel/arch/config.
This indicates that it should not be built.

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.

Installing /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}

Running depmod... done.
dkms autoinstall on ${KERNEL_VER}/${KERNEL_ARCH} succeeded for dkms_test
dkms autoinstall on ${KERNEL_VER}/${KERNEL_ARCH} was skipped for dkms_build_exclusive_test
EOF
run_status_with_expected_output 'dkms_build_exclusive_test' << EOF
dkms_build_exclusive_test/1.0: added
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
EOF

echo 'Unbuilding the test module'
run_with_expected_output dkms unbuild -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test-1.0 for kernel ${KERNEL_VER} (${KERNEL_ARCH}).
Before uninstall, this module version was ACTIVE on this kernel.

Deleting /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}

Running depmod... done.
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0: added
EOF

echo 'Adding failing test module by directory'
run_with_expected_output dkms add test/dkms_failing_test-1.0 << EOF
Creating symlink /var/lib/dkms/dkms_failing_test/1.0/source -> /usr/src/dkms_failing_test-1.0
EOF

echo "Running dkms autoinstall (1 x skip, 1 x fail, 1 x pass) (expected error)"
run_with_expected_error 11 dkms autoinstall -k "${KERNEL_VER}" << EOF
Warning: The /var/lib/dkms/dkms_build_exclusive_test/1.0/${KERNEL_VER}/${KERNEL_ARCH}/dkms.conf
for module dkms_build_exclusive_test includes a BUILD_EXCLUSIVE directive
which does not match this kernel/arch/config.
This indicates that it should not be built.

Cleaning build area... done.
Building module(s)...(bad exit status: 2)
Failed command:
make -j1 KERNELRELEASE=${KERNEL_VER} all <omitting possibly set CC/LD/... flags>
Error! Bad return status for module build on kernel: ${KERNEL_VER} (${KERNEL_ARCH})
Consult /var/lib/dkms/dkms_failing_test/1.0/build/make.log for more information.

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.

Installing /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}

Running depmod... done.
dkms autoinstall on ${KERNEL_VER}/${KERNEL_ARCH} succeeded for dkms_test
dkms autoinstall on ${KERNEL_VER}/${KERNEL_ARCH} was skipped for dkms_build_exclusive_test
dkms autoinstall on ${KERNEL_VER}/${KERNEL_ARCH} failed for dkms_failing_test(10)

Error! One or more modules failed to install during autoinstall.
Refer to previous errors for more information.
EOF

echo 'Removing failing test module'
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_failing_test -v 1.0 << EOF
Module dkms_failing_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Module dkms_failing_test 1.0 is not built for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Deleting module dkms_failing_test-1.0 completely from the DKMS tree.
EOF
echo 'Removing /usr/src/dkms_failing_test-1.0'
rm -r /usr/src/dkms_failing_test-1.0

echo 'Removing the test module'
run_with_expected_output dkms remove --all -m dkms_test -v 1.0 << EOF
Module dkms_test-1.0 for kernel ${KERNEL_VER} (${KERNEL_ARCH}).
Before uninstall, this module version was ACTIVE on this kernel.

Deleting /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}

Running depmod... done.
Deleting module dkms_test-1.0 completely from the DKMS tree.
EOF
run_status_with_expected_output 'dkms_test' << EOF
EOF
echo 'Removing /usr/src/dkms_test-1.0'
rm -r /usr/src/dkms_test-1.0

echo 'Adding the build-exclusive dependencies test module by directory'
run_with_expected_output dkms add test/dkms_build_exclusive_dependencies_test-1.0 << EOF
Creating symlink /var/lib/dkms/dkms_build_exclusive_dependencies_test/1.0/source -> /usr/src/dkms_build_exclusive_dependencies_test-1.0
EOF
run_status_with_expected_output 'dkms_build_exclusive_dependencies_test' << EOF
dkms_build_exclusive_dependencies_test/1.0: added
EOF
if ! [[ -d /usr/src/dkms_build_exclusive_dependencies_test-1.0 ]] ; then
    echo >&2 'Error: directory /usr/src/dkms_build_exclusive_dependencies_test-1.0 was not created'
    return 1
fi

echo "Running dkms autoinstall (2 x skip, with dependency)"
run_with_expected_output dkms autoinstall -k "${KERNEL_VER}" << EOF
Warning: The /var/lib/dkms/dkms_build_exclusive_test/1.0/${KERNEL_VER}/${KERNEL_ARCH}/dkms.conf
for module dkms_build_exclusive_test includes a BUILD_EXCLUSIVE directive
which does not match this kernel/arch/config.
This indicates that it should not be built.
Warning: The /var/lib/dkms/dkms_build_exclusive_dependencies_test/1.0/${KERNEL_VER}/${KERNEL_ARCH}/dkms.conf
for module dkms_build_exclusive_dependencies_test includes a BUILD_EXCLUSIVE directive
which does not match this kernel/arch/config.
This indicates that it should not be built.
dkms autoinstall on ${KERNEL_VER}/${KERNEL_ARCH} was skipped for dkms_build_exclusive_test dkms_build_exclusive_dependencies_test
EOF
run_status_with_expected_output 'dkms_build_exclusive_test' << EOF
dkms_build_exclusive_test/1.0: added
EOF
run_status_with_expected_output 'dkms_build_exclusive_dependencies_test' << EOF
dkms_build_exclusive_dependencies_test/1.0: added
EOF

echo 'Removing the build-exclusive dependencies test module'
run_with_expected_output dkms remove --all -m dkms_build_exclusive_dependencies_test -v 1.0 << EOF
Deleting module dkms_build_exclusive_dependencies_test-1.0 completely from the DKMS tree.
EOF
run_status_with_expected_output 'dkms_build_exclusive_dependencies_test' << EOF
EOF
echo 'Removing /usr/src/dkms_build_exclusive_dependencies_test-1.0'
rm -r /usr/src/dkms_build_exclusive_dependencies_test-1.0

echo 'Removing the build-exclusive test module'
run_with_expected_output dkms remove --all -m dkms_build_exclusive_test -v 1.0 << EOF
Deleting module dkms_build_exclusive_test-1.0 completely from the DKMS tree.
EOF
run_status_with_expected_output 'dkms_build_exclusive_test' << EOF
EOF
echo 'Removing /usr/src/dkms_build_exclusive_test-1.0'
rm -r /usr/src/dkms_build_exclusive_test-1.0

echo 'Checking that the environment is clean again'
check_no_dkms_test

############################################################################
### Testing os-release detection                                         ###
############################################################################
echo "Backing up /etc/os-release and /usr/lib/os-release"
osrelease_cleanup() {
    rm -f _os-release
    mv _etc-os-release /etc/os-release &>/dev/null || :
    mv _usrlib-os-release /usr/lib/os-release &>/dev/null || :
}

for f in /etc/os-release /usr/lib/os-release; do
    if [ -e "$f" ]; then
        cp --preserve=all -f "$f" _os-release
        break
    fi
done
[ -f _os-release ] || { echo >&2 "Error: file os-release not found"; exit 1; }
trap osrelease_cleanup EXIT

mv_osrelease() {
    if [ -f "$1" ]; then
       mv "$1" "$2" || { echo >&2 "Error: could not move os-release $1"; exit 1; }
    fi
}
mv_osrelease "/etc/os-release" "_etc-os-release"
mv_osrelease "/usr/lib/os-release" "_usrlib-os-release"

echo "Adding the dkms_test-1.0 module with no os-release files (expected error)"
run_with_expected_error 4 dkms add test/dkms_test-1.0 << EOF

Error! System is missing os-release file.
EOF

echo "Creating /etc/os-release"
cp -f _os-release /etc/os-release
echo "Adding the dkms_test-1.0 module with file /etc/os-release"
run_with_expected_output dkms add test/dkms_test-1.0 << EOF
Creating symlink /var/lib/dkms/dkms_test/1.0/source -> /usr/src/dkms_test-1.0
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0: added
EOF

echo 'Removing dkms_test module'
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Module dkms_test 1.0 is not built for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Deleting module dkms_test-1.0 completely from the DKMS tree.
EOF
echo "Removing /usr/src/dkms_test-1.0"
rm -r /usr/src/dkms_test-1.0
echo "Deleting /etc/os-release"
rm -f /etc/os-release

echo "Creating /usr/lib/os-release"
cp -f _os-release /etc/os-release
echo "Adding the dkms_test-1.0 module with file /usr/lib/os-release"
run_with_expected_output dkms add test/dkms_test-1.0 << EOF
Creating symlink /var/lib/dkms/dkms_test/1.0/source -> /usr/src/dkms_test-1.0
EOF
run_status_with_expected_output 'dkms_test' << EOF
dkms_test/1.0: added
EOF

echo 'Removing dkms_test module'
run_with_expected_output dkms remove -k "${KERNEL_VER}" -m dkms_test -v 1.0 << EOF
Module dkms_test 1.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Module dkms_test 1.0 is not built for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Deleting module dkms_test-1.0 completely from the DKMS tree.
EOF
echo "Removing /usr/src/dkms_test-1.0"
rm -r /usr/src/dkms_test-1.0
echo "Deleting /usr/lib/os-release"
rm -f /usr/lib/os-release

echo "Restoring /etc/os-release and /usr/bin/os-release"
osrelease_cleanup
trap - EXIT

echo 'Checking that the environment is clean again'
check_no_dkms_test

############################################################################
### Testing 'broken' status                                              ###
############################################################################

echo
echo 'Running BROKEN tests'
echo

echo 'Adding the test module by directory'
run_with_expected_output dkms add test/dkms_test-1.0 << EOF
Creating symlink /var/lib/dkms/dkms_test/1.0/source -> /usr/src/dkms_test-1.0
EOF

echo ' Removing symlink /var/lib/dkms/dkms_test/1.0/source'
rm /var/lib/dkms/dkms_test/1.0/source

echo 'Checking broken status'
run_with_expected_output dkms status dkms_test/1.0 << EOF
dkms_test/1.0: broken

Error! dkms_test/1.0: Missing the module source directory or the symbolic link pointing to it.
Manual intervention is required!
EOF

echo 'Re-adding the test module'
run_with_expected_output dkms add dkms_test/1.0 << EOF
Creating symlink /var/lib/dkms/dkms_test/1.0/source -> /usr/src/dkms_test-1.0
EOF

echo ' Removing symlink /var/lib/dkms/dkms_test/1.0/source'
rm /var/lib/dkms/dkms_test/1.0/source

echo 'Building broken test module (expected erorr)'
run_with_expected_error 4 dkms build dkms_test/1.0 << EOF

Error! dkms_test/1.0 is broken!
Missing the source directory or the symbolic link pointing to it.
Manual intervention is required!
EOF

echo 'Installing broken test module (expected erorr)'
run_with_expected_error 4 dkms install dkms_test/1.0 << EOF

Error! dkms_test/1.0 is broken!
Missing the source directory or the symbolic link pointing to it.
Manual intervention is required!
EOF

echo 'Unbuild broken test module (expected erorr)'
run_with_expected_error 4 dkms unbuild dkms_test/1.0 << EOF

Error! dkms_test/1.0 is broken!
Missing the source directory or the symbolic link pointing to it.
Manual intervention is required!
EOF

echo 'Uninstall broken test module (expected erorr)'
run_with_expected_error 4 dkms uninstall dkms_test/1.0 << EOF

Error! dkms_test/1.0 is broken!
Missing the source directory or the symbolic link pointing to it.
Manual intervention is required!
EOF

echo 'Adding the multiver test module 1.0 by directory'
run_with_expected_output dkms add test/dkms_multiver_test/1.0 << EOF
Creating symlink /var/lib/dkms/dkms_multiver_test/1.0/source -> /usr/src/dkms_multiver_test-1.0
EOF

echo 'Checking broken status'
run_with_expected_output dkms status << EOF
dkms_multiver_test/1.0: added
dkms_test/1.0: broken

Error! dkms_test/1.0: Missing the module source directory or the symbolic link pointing to it.
Manual intervention is required!
EOF

echo 'Remove broken test module (expected erorr)'
run_with_expected_error 4 dkms remove dkms_test/1.0 << EOF

Error! dkms_test/1.0 is broken!
Missing the source directory or the symbolic link pointing to it.
Manual intervention is required!
EOF

echo 'Re-adding the test module'
run_with_expected_output dkms add dkms_test/1.0 << EOF
Creating symlink /var/lib/dkms/dkms_test/1.0/source -> /usr/src/dkms_test-1.0
EOF

echo ' Removing source tree /usr/src/dkms_test-1.0/'
rm -rf /usr/src/dkms_test-1.0/

echo 'Checking broken status'
run_with_expected_output dkms status << EOF
dkms_multiver_test/1.0: added
dkms_test/1.0: broken

Error! dkms_test/1.0: Missing the module source directory or the symbolic link pointing to it.
Manual intervention is required!
EOF

echo 'Removing dkms_multiver_test'
dkms remove dkms_multiver_test/1.0 -k "${KERNEL_VER}" > /dev/null

echo 'Removing dkms_test'
rm -rf /var/lib/dkms/dkms_test/

echo 'Adding and building the test module by directory'
set_signing_message "dkms_test" "1.0"
run_with_expected_output dkms build test/dkms_test-1.0 -k "${KERNEL_VER}" << EOF
Creating symlink /var/lib/dkms/dkms_test/1.0/source -> /usr/src/dkms_test-1.0

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.
EOF

echo 'Adding and building the multiver test module 1.0 by directory'
set_signing_message "dkms_multiver_test" "1.0"
run_with_expected_output dkms build test/dkms_multiver_test/1.0 -k "${KERNEL_VER}" << EOF
Creating symlink /var/lib/dkms/dkms_multiver_test/1.0/source -> /usr/src/dkms_multiver_test-1.0

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.
EOF

echo ' Removing symlink /var/lib/dkms/dkms_multiver_test/1.0/source'
rm /var/lib/dkms/dkms_multiver_test/1.0/source

echo 'Adding and building the multiver test module 2.0 by directory'
set_signing_message "dkms_multiver_test" "2.0"
run_with_expected_output dkms build test/dkms_multiver_test/2.0 -k "${KERNEL_VER}" << EOF
Creating symlink /var/lib/dkms/dkms_multiver_test/2.0/source -> /usr/src/dkms_multiver_test-2.0

Cleaning build area... done.
Building module(s)... done.
${SIGNING_MESSAGE}Cleaning build area... done.
EOF

echo 'Running dkms autoinstall'
run_with_expected_output dkms autoinstall -k "${KERNEL_VER}" << EOF

Error! dkms_multiver_test/1.0 is broken! Missing the source directory or the symbolic link pointing to it.
Manual intervention is required!

Installing /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}

Running depmod... done.
dkms autoinstall on ${KERNEL_VER}/${KERNEL_ARCH} succeeded for dkms_test
EOF
run_with_expected_output dkms status << EOF
dkms_multiver_test/1.0: broken

Error! dkms_multiver_test/1.0: Missing the module source directory or the symbolic link pointing to it.
Manual intervention is required!
dkms_multiver_test/2.0, ${KERNEL_VER}, ${KERNEL_ARCH}: built
dkms_test/1.0, ${KERNEL_VER}, ${KERNEL_ARCH}: installed
EOF

echo 'Removing all modules'
echo ' Removing the test module'
run_with_expected_output dkms remove dkms_test/1.0 -k "${KERNEL_VER}" << EOF
Module dkms_test-1.0 for kernel ${KERNEL_VER} (${KERNEL_ARCH}).
Before uninstall, this module version was ACTIVE on this kernel.

Deleting /lib/modules/${KERNEL_VER}/${expected_dest_loc}/dkms_test.ko${mod_compression_ext}

Running depmod... done.
Deleting module dkms_test-1.0 completely from the DKMS tree.
EOF

echo ' Removing the multi_ver_test 2.0 module'
run_with_expected_output dkms remove -m dkms_multiver_test -v 2.0 -k "${KERNEL_VER}" << EOF
Module dkms_multiver_test 2.0 is not installed for kernel ${KERNEL_VER} (${KERNEL_ARCH}). Skipping...
Deleting module dkms_multiver_test-2.0 completely from the DKMS tree.
EOF

echo ' Removing directories: /var/lib/dkms/dkms_test/ /var/lib/dkms/dkms_multiver_test /usr/src/dkms_test-1.0 /usr/src/dkms_multiver_test-?.0'
rm -rf /var/lib/dkms/dkms_test/ /var/lib/dkms/dkms_multiver_test /usr/src/dkms_test-1.0 /usr/src/dkms_multiver_test-?.0

echo 'Checking that the environment is clean again'
check_no_dkms_test

echo
echo 'End of BROKEN tests'
echo

echo 'All tests successful :)'
