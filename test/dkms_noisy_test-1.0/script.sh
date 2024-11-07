#!/bin/sh

echo "$0" "$@"
echo "$1: line 1"
echo "$1: line 2/stderr" >&2
echo "$1: line 3"
echo "$1: line 4/stderr" >&2
echo "$1: line 5"
