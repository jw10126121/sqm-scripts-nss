#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../sqm-scripts-nss/files" && pwd)
sh -n "$SCRIPT_DIR/nss-zk.qos"
