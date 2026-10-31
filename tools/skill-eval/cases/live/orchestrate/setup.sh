#!/usr/bin/env bash
set -eu
exec bash "$(cd "$(dirname "$0")" && pwd)/../../../fixtures/setup-ledger.sh" plain
