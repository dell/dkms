#!/bin/sh
/lib/modules/"$1"/build/scripts/sign-file sha512 /root/mok.priv /root/mok.der "$2"
