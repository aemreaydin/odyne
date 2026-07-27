#!/usr/bin/env bash
#
# Build + test everything, for shells without PowerShell.
#
# scripts/build.ps1 and scripts/test.ps1 are the canonical runners and do more than this
# (odinfmt pass, package auto-discovery, per-package failure summary). They are `#!/usr/bin/env
# pwsh` and run anywhere PowerShell is installed — but pwsh is NOT installed on the macOS
# dev machine as of 2026-07-27, hence this. Prefer the .ps1 scripts where pwsh exists;
# `brew install powershell` makes that true.
#
# The flags below are copied from scripts/common.ps1 and MUST be kept in sync with it.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

ODIN_FLAGS=(
	-vet
	-vet-cast
	-vet-tabs
	-vet-using-param
	-strict-style
	-warnings-as-errors
	-error-pos-style:unix
)
ODIN_COLLECTIONS=(-collection:engine=engine)

# vendor:sdl3 links `system:SDL3` off Windows, so point the linker at Homebrew's lib dir.
BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
ODIN_LINK_FLAGS=("-extra-linker-flags:-L${BREW_PREFIX}/lib")

mkdir -p build build/tests

failed=()
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

run() { # run <label> <cmd...>
	local label="$1"; shift
	step "$label"
	if ! "$@"; then failed+=("$label"); fi
}

# Unit tests — packages carrying *_test.odin. engine/platform's tier 1 is pure logic;
# anything needing a real window lives in tests/platform below, not here.
for pkg in engine/core engine/core/memory engine/core/containers/handle_pool engine/platform; do
	[[ -d $pkg ]] || continue
	compgen -G "$pkg/*_test.odin" >/dev/null || continue
	run "test $pkg" odin test "$pkg" "${ODIN_FLAGS[@]}" "${ODIN_COLLECTIONS[@]}" \
		"${ODIN_LINK_FLAGS[@]}" "-out:build/tests/${pkg//\//_}"
done

# The platform harness — a main() so tier 2/3 run on the main thread with real windows.
run "build tests/platform" odin build tests/platform "${ODIN_FLAGS[@]}" \
	"${ODIN_COLLECTIONS[@]}" "${ODIN_LINK_FLAGS[@]}" -out:build/platform-tests
if [[ -x build/platform-tests ]]; then
	run "run tests/platform" ./build/platform-tests
fi

run "build examples/testbed" odin build examples/testbed "${ODIN_FLAGS[@]}" \
	"${ODIN_COLLECTIONS[@]}" "${ODIN_LINK_FLAGS[@]}" -out:build/testbed

if ((${#failed[@]})); then
	printf '\n\033[31m%d failed:\033[0m\n' "${#failed[@]}"
	printf '  %s\n' "${failed[@]}"
	exit 1
fi
printf '\n\033[32mAll green.\033[0m\n'
