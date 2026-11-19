#!/usr/bin/env bash

set -uo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
cd "$repo_root"

kcov_bin="${KCOV:-kcov}"
coverage_dir="$repo_root/coverage"
run_dir="$repo_root/bin/coverage"
unit_binary="$repo_root/bin/unit-tests-coverage"
binding_binary="$repo_root/bin/c-binding-unit-tests-coverage"
e2e_binary="$repo_root/bin/e2e-tests-coverage"
source_paths="$repo_root/src/rifle,$repo_root/src/vtab,$repo_root/bindings/c/rifle.odin"

test_flags=(
	-collection:rifle=./src
	-vet
	-debug
	-o:none
	-use-single-module
	-keep-executable
	-define:ODIN_TEST_ALWAYS_REPORT_MEMORY=true
	-define:ODIN_TEST_RANDOM_SEED=123
	-define:ODIN_TEST_THREADS=1
)

if ! command -v "$kcov_bin" >/dev/null 2>&1; then
	echo "kcov is required to generate coverage" >&2
	exit 127
fi

build_test_binary() {
	local package=$1
	local binary=$2
	local status=0

	odin test "$package" "${test_flags[@]}" "-out:$binary" || status=$?
	if [[ ! -x "$binary" ]]; then
		echo "Odin did not produce the coverage test binary: $binary" >&2
		((status != 0)) || status=1
		exit "$status"
	fi
}

collect_coverage() {
	local name=$1
	local binary=$2
	local output="$run_dir/$name"
	local status=0

	"$kcov_bin" --clean --include-path="$source_paths" "$output" "$binary" || status=$?
	if ! find "$output" -mindepth 2 -type f -name coverage.json -print -quit | grep -q .; then
		echo "kcov did not produce the $name coverage report" >&2
		((status != 0)) || status=1
		exit "$status"
	fi

	if ((status != 0)); then
		echo "The $name tests failed with status $status; their coverage data will still be merged"
	fi
}

rm -rf "$coverage_dir" "$run_dir"
mkdir -p "$repo_root/bin" "$run_dir"
rm -f "$unit_binary" "$binding_binary" "$e2e_binary"

build_test_binary ./test/unit "$unit_binary"
build_test_binary ./bindings/c "$binding_binary"
build_test_binary ./test/e2e "$e2e_binary"

collect_coverage unit "$unit_binary"
collect_coverage bindings "$binding_binary"
collect_coverage e2e "$e2e_binary"

if ! "$kcov_bin" --clean --merge \
		"$coverage_dir" \
		"$run_dir/unit" \
		"$run_dir/bindings" \
		"$run_dir/e2e"; then
	echo "kcov failed to merge the coverage reports" >&2
	exit 1
fi

if [[ ! -f "$coverage_dir/kcov-merged/coverage.json" ]]; then
	echo "kcov did not produce the merged coverage report" >&2
	exit 1
fi

echo "Merged coverage report generated at $coverage_dir/index.html"
