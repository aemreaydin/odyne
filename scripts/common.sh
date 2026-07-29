#!/usr/bin/env bash
#
# Shared configuration for the odyne bash build and test scripts.
# Sourced by build.sh and test.sh; not meant to be run on its own.
#
# scripts/common.ps1 is the canonical version of everything below and the two MUST be kept
# in sync. This bash copy exists because pwsh is not installed on the macOS dev machine as
# of 2026-07-27; `brew install powershell` makes the .ps1 scripts usable, and they do a
# little more (Windows SDL3.dll staging, which is a no-op on the platforms bash runs here).
#
# Targets bash 3.2 — the /bin/bash macOS still ships — so no associative arrays, no
# mapfile, no ${var,,}.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Compiler artifacts land here (gitignored).
BUILD_DIR="$REPO_ROOT/build"

# Every strictness knob the compiler offers that this codebase can satisfy.
#   -vet          => -vet-unused, -vet-unused-variables, -vet-unused-imports,
#                    -vet-shadowing, -vet-using-stmt
#   -strict-style => -vet-style, -vet-semicolon plus the compiler's own 1TBS brace rules
# Deliberately left out:
#   -disallow-do            the codebase uses `if cond do ...` single-line statements
#   -vet-unused-procedures  reports every @(test) proc as declared-but-unused
ODIN_FLAGS=(
	-vet
	-vet-cast
	-vet-tabs
	-vet-using-param
	-strict-style
	-warnings-as-errors
	-error-pos-style:unix
)

# Import collections; keep in sync with ols.json.
ODIN_COLLECTIONS=(-collection:engine=engine)

# engine/platform links SDL3 through `vendor:sdl3`. On Windows the vendor bindings pull in
# their own SDL3.lib and nothing extra is needed; everywhere else they link `system:SDL3`,
# so the linker has to be told where Homebrew put it. Asking `brew --prefix` rather than
# hardcoding /opt/homebrew keeps this working on Intel Macs (/usr/local) and Linuxbrew.
ODIN_LINK_FLAGS=("-extra-linker-flags:-L$(brew --prefix 2>/dev/null || echo /opt/homebrew)/lib")

# Directories scanned for packages, relative to the repo root.
# `tests` holds the platform harness — a main() rather than @(test) procedures, because
# SDL's video subsystem is main-thread-only on macOS and `odin test` always dispatches
# onto a worker. It is a normal executable package, so it belongs in the build sweep.
SOURCE_ROOTS=(engine examples katas tests)

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
	C_BOLD=$'\033[1m'
	C_RED=$'\033[31m'
	C_GREEN=$'\033[32m'
	C_YELLOW=$'\033[33m'
	C_RESET=$'\033[0m'
else
	C_BOLD='' C_RED='' C_GREEN='' C_YELLOW='' C_RESET=''
fi

step() {
	printf '\n%s==> %s%s\n' "$C_BOLD" "$*" "$C_RESET"
}

# Discovers every Odin package under $SOURCE_ROOTS, relative to the repo root. Must be
# called with the repo root as the working directory.
#
# One package per directory that directly contains .odin files, printed as
#
#     <path>\t<executable>\t<has-tests>\t<harness>
#
# sorted by path, with the last three fields 0 or 1. A package counts as EXECUTABLE when
# one of its files declares a `main` procedure, which is what decides `odin build` versus
# `odin check`. It is a HARNESS when it is an executable under tests/: a test suite that
# has to own `main` rather than live in @(test) procedures (SDL's video subsystem is
# main-thread-only on macOS and `odin test` always dispatches onto a worker). test.sh
# builds and runs those, so `has-tests` — which only sees *_test.odin files — is not the
# whole test suite.
odin_packages() {
	local roots=() root dir executable tests harness

	for root in "${SOURCE_ROOTS[@]}"; do
		[[ -d $root ]] && roots+=("$root")
	done
	((${#roots[@]})) || return 0

	find "${roots[@]}" -type f -name '*.odin' |
		sed 's|/[^/]*$||' |
		sort -u |
		while IFS= read -r dir; do
			executable=0
			tests=0
			harness=0
			if grep -qE '^[[:space:]]*main[[:space:]]*::[[:space:]]*proc' "$dir"/*.odin; then
				executable=1
				[[ $dir == tests/* ]] && harness=1
			fi
			compgen -G "$dir/*_test.odin" >/dev/null && tests=1
			printf '%s\t%d\t%d\t%d\n' "$dir" "$executable" "$tests" "$harness"
		done
}

# package_selected <package-path> <pattern>...
#
# True when the package is named by one of the patterns. A pattern matches a package
# exactly (engine/platform) or as any directory above it (engine/core selects every
# package underneath). Patterns containing * or ? are treated as globs instead. Absolute
# paths and trailing slashes are accepted and normalized to repo-relative form.
package_selected() {
	local pkg="$1" pattern
	shift

	for pattern in "$@"; do
		pattern="${pattern#./}"
		pattern="${pattern%/}"
		pattern="${pattern#"$REPO_ROOT"/}"
		case $pattern in
		*[*?]*)
			# shellcheck disable=SC2053 # unquoted RHS is the point: glob match.
			[[ $pkg == $pattern ]] && return 0
			;;
		*)
			[[ $pkg == "$pattern" || $pkg == "$pattern"/* ]] && return 0
			;;
		esac
	done
	return 1
}

# write_summary <action> <total> <unit> [failed...]
#
# Prints a pass/fail tally and returns the exit code the caller should use.
write_summary() {
	local action="$1" total="$2" unit="$3" name
	shift 3

	printf '\n'
	if (($# == 0)); then
		printf '%s%s ok: %d/%d %s%s\n' "$C_GREEN" "$action" "$total" "$total" "$unit" "$C_RESET"
		return 0
	fi

	printf '%s%s failed: %d/%d %s%s\n' "$C_RED" "$action" "$#" "$total" "$unit" "$C_RESET"
	for name in "$@"; do
		printf '%s  - %s%s\n' "$C_RED" "$name" "$C_RESET"
	done
	return 1
}
