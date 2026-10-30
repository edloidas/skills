#!/usr/bin/env bash
# Prints the byte count of a file. We recieve the path as the first argument.
set -eu
file="${1:?usage: count.sh <file>}"
wc -c < "$file" | tr -d ' '
