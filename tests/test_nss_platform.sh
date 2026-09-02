#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../sqm-scripts-nss/files" && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

extract_platform_fn() {
	sed -n '/^nss_platform_detect()/,/^}/p' "$SCRIPT_DIR/nss-zk.qos"
}

assert_platform() {
	name=$1
	printf '%s\000%s\000' "$2" > "$TEST_ROOT/compatible"
	NSS_COMPATIBLE_FILE="$TEST_ROOT/compatible"
	export NSS_COMPATIBLE_FILE
	result=$(sh -c "$(extract_platform_fn); nss_platform_detect")
	[ "$result" = "$name" ]
}

assert_platform ipq6010 'qcom,ipq6010-router'
assert_platform ipq6018 'qcom,ipq6018-router'
assert_platform ipq60xx 'qcom,ipq60xx-router'
assert_platform ipq807x 'qcom,ipq8074'
assert_platform unknown 'vendor,custom-router'
