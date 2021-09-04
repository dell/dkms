#!/bin/sh
/lib/modules/"$1"/build/scripts/sign-file sha512 /root/dkms.key /root/dkms.der "$2"
