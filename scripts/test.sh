#!/usr/bin/env bash
#
# Runs both tiers of the odyne test suite, for shells without PowerShell.
#
# scripts/test.ps1 is the canonical runner; this is a port of it, and the two are expected
# to behave the same. The one thing missing here is staging SDL3.dll beside a freshly
# linked binary, which Windows needs and nothing else does.
#
# Tier 1 — every package containing *_test.odin files, run with `odin test`.
# Tier 2 — every executable package under tests/: a HARNESS, built and then run. Those own
# `main` instead of using @(test) procedures because they need real windows, and
# `core:testing`'s runner dispatches onto a worker thread where SDL's video subsystem is
# unusable on macOS. Both tiers use the project's full vet/style flag set (see
# scripts/common.sh), and both write binaries to build/tests/ so they stay out of the repo
# root.
#
# All packages are attempted even if an earlier one fails, so a single run reports every
# failing package. Exits non-zero if anything failed.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
	cat <<'EOF'
Usage: scripts/test.sh [options] [path...]

Runs `odin test` over every package holding *_test.odin files, then builds and runs every
harness package under tests/.

Arguments:
  path...           Limit the run to one or more locations, relative to the repo root. A
                    path matches a package exactly (engine/platform) or as any directory
                    above it (engine/core runs every package underneath). Paths containing
                    * or ? are matched as globs — quote them so the shell does not expand
                    them first. Omit to run everything.

Options:
  -t, --threads N   Tier-1 test runner thread count (1-256). Defaults to 1: engine/platform
                    shares package state and drives per-thread OS event queues, so its
                    tests deadlock under the parallel runner. The suites are
                    sub-millisecond, so running serially costs nothing worth reclaiming.
                    Harnesses ignore this — they are single-threaded by construction.
      --in-process  Run harness cases in one process instead of one child process per case.
                    Faster, but a crash then takes the whole run down with it rather than
                    one case.
  -h, --help        Print this help and exit.

Examples:
  scripts/test.sh
  scripts/test.sh engine/platform
  scripts/test.sh tests/platform --in-process
  scripts/test.sh 'katas/*' --threads 8
EOF
}

die() {
	printf '%s%s%s\n' "$C_RED" "$*" "$C_RESET" >&2
	exit 1
}

threads=1
in_process=0
paths=()

while (($#)); do
	case $1 in
	-h | --help)
		usage
		exit 0
		;;
	-t | --threads)
		[[ $# -ge 2 ]] || die "$1 needs a value"
		threads="$2"
		shift 2
		;;
	--threads=*)
		threads="${1#*=}"
		shift
		;;
	--in-process)
		in_process=1
		shift
		;;
	--)
		shift
		paths+=("$@")
		break
		;;
	-*)
		die "unknown option: $1 (try --help)"
		;;
	*)
		paths+=("$1")
		shift
		;;
	esac
done

[[ $threads =~ ^[0-9]+$ ]] && ((threads >= 1 && threads <= 256)) ||
	die "--threads must be between 1 and 256, got: $threads"

cd "$REPO_ROOT" || die "cannot enter $REPO_ROOT"

pkg_paths=()
pkg_harness=()
while IFS=$'\t' read -r path executable has_tests harness; do
	((has_tests || harness)) || continue
	pkg_paths+=("$path")
	pkg_harness+=("$harness")
done < <(odin_packages)

if ((${#pkg_paths[@]} == 0)); then
	printf '%sNo tests found under: %s%s\n' "$C_YELLOW" "${SOURCE_ROOTS[*]}" "$C_RESET"
	exit 0
fi

if ((${#paths[@]})); then
	selected_paths=()
	selected_harness=()
	for ((i = 0; i < ${#pkg_paths[@]}; i++)); do
		if package_selected "${pkg_paths[i]}" "${paths[@]}"; then
			selected_paths+=("${pkg_paths[i]}")
			selected_harness+=("${pkg_harness[i]}")
		fi
	done

	if ((${#selected_paths[@]} == 0)); then
		# A typo'd path silently running zero tests would read as success, so fail loudly.
		printf '%sNo tested package matches: %s%s\n' "$C_RED" "${paths[*]}" "$C_RESET" >&2
		printf '%sAvailable:%s\n' "$C_YELLOW" "$C_RESET" >&2
		for path in "${pkg_paths[@]}"; do
			printf '%s  %s%s\n' "$C_YELLOW" "$path" "$C_RESET" >&2
		done
		exit 1
	fi

	pkg_paths=("${selected_paths[@]}")
	pkg_harness=("${selected_harness[@]}")
fi

mkdir -p "$BUILD_DIR/tests" || die "cannot create $BUILD_DIR/tests"

failed=()
for ((i = 0; i < ${#pkg_paths[@]}; i++)); do
	pkg="${pkg_paths[i]}"
	# Package leaf names repeat across the tree (engine/.../handle_pool and
	# katas/handle_pool), so name the binary after the full path.
	out="build/tests/${pkg//\//_}"

	if ((pkg_harness[i])); then
		step "harness $pkg"
		if ! odin build "$pkg" "${ODIN_FLAGS[@]}" "${ODIN_COLLECTIONS[@]}" \
			"${ODIN_LINK_FLAGS[@]}" "-out:$out"; then
			failed+=("$pkg")
			continue
		fi
		harness_args=()
		((in_process)) && harness_args=(--in-process)
		"./$out" ${harness_args[@]+"${harness_args[@]}"} || failed+=("$pkg")
		continue
	fi

	step "test $pkg"
	odin test "$pkg" "${ODIN_FLAGS[@]}" "${ODIN_COLLECTIONS[@]}" "${ODIN_LINK_FLAGS[@]}" \
		"-out:$out" "-define:ODIN_TEST_THREADS=$threads" || failed+=("$pkg")
done

write_summary 'Tests' "${#pkg_paths[@]}" packages ${failed[@]+"${failed[@]}"}
