# Shared configuration for the odyne build and test scripts.
# Dot-sourced by build.ps1 and test.ps1; not meant to be run on its own.

$RepoRoot = Split-Path -Parent $PSScriptRoot

# Every strictness knob the compiler offers that this codebase can satisfy.
#   -vet          => -vet-unused, -vet-unused-variables, -vet-unused-imports,
#                    -vet-shadowing, -vet-using-stmt
#   -strict-style => -vet-style, -vet-semicolon plus the compiler's own 1TBS brace rules
# Deliberately left out:
#   -disallow-do            the codebase uses `if cond do ...` single-line statements
#   -vet-unused-procedures  reports every @(test) proc as declared-but-unused
$OdinFlags = @(
	'-vet'
	'-vet-cast'
	'-vet-tabs'
	'-vet-using-param'
	'-strict-style'
	'-warnings-as-errors'
	'-error-pos-style:unix'
)

# Import collections; keep in sync with ols.json.
$OdinCollections = @('-collection:engine=engine')

# engine/platform links SDL3 through `vendor:sdl3`. On Windows the vendor bindings pull in
# their own SDL3.lib and nothing extra is needed; everywhere else they link `system:SDL3`,
# so the linker has to be told where Homebrew put it. Asking `brew --prefix` rather than
# hardcoding /opt/homebrew keeps this working on Intel Macs (/usr/local) and Linuxbrew.
$OdinLinkFlags = @()
if (-not $IsWindows) {
	$brewPrefix = & brew --prefix 2>$null
	if ($LASTEXITCODE -eq 0 -and $brewPrefix) {
		$OdinLinkFlags += "-extra-linker-flags:-L$brewPrefix/lib"
	}
}

# Directories scanned for packages, relative to the repo root.
# `tests` holds the platform harness — a main() rather than @(test) procedures, because
# SDL's video subsystem is main-thread-only on macOS and `odin test` always dispatches
# onto a worker. It is a normal executable package, so it belongs in the build sweep.
$SourceRoots = @('engine', 'examples', 'katas', 'tests')

# Compiler artifacts land here (gitignored).
$BuildDir = Join-Path $RepoRoot 'build'

function Get-OdinPackage {
	<#
	.SYNOPSIS
		Discovers every Odin package under $SourceRoots.
	.DESCRIPTION
		One package per directory that directly contains .odin files. A package
		counts as an executable when one of its files declares a `main` procedure,
		which is what decides `odin build` versus `odin check`.

		A package is a HARNESS when it is an executable under tests/: a test suite
		that has to own `main` rather than live in @(test) procedures (SDL's video
		subsystem is main-thread-only on macOS and `odin test` always dispatches onto
		a worker). test.ps1 builds and runs those, so `HasTests` — which only sees
		*_test.odin files — is not the whole test suite.
	#>
	$roots = $SourceRoots |
		ForEach-Object { Join-Path $RepoRoot $_ } |
		Where-Object { Test-Path $_ }
	if (-not $roots) { return @() }

	Get-ChildItem -Path $roots -Recurse -File -Filter '*.odin' |
		Group-Object DirectoryName |
		Sort-Object Name |
		ForEach-Object {
			$files = $_.Group
			$relative = [System.IO.Path]::GetRelativePath($RepoRoot, $_.Name).Replace('\', '/')
			$executable = [bool](Select-String -Path $files.FullName -Pattern '^\s*main\s*::\s*proc' -List -Quiet)
			[pscustomobject]@{
				Path         = $relative
				Name         = Split-Path $_.Name -Leaf
				IsExecutable = $executable
				HasTests     = [bool](@($files | Where-Object { $_.Name -like '*_test.odin' }).Count)
				IsHarness    = $executable -and $relative.StartsWith('tests/')
			}
		}
}

function Sync-SdlRuntime {
	<#
	.SYNOPSIS
		Puts SDL3.dll next to a freshly linked binary. Windows only; a no-op elsewhere.
	.DESCRIPTION
		engine/platform links SDL3 through `vendor:sdl3`, which on Windows resolves against
		the vendored SDL3.lib — an import library. At RUN time the loader then looks for
		SDL3.dll in the executable's own directory first, and nothing in the Odin toolchain
		puts it there, so a perfectly linked binary dies with
		"SDL3.dll: cannot open shared object file". Everywhere else `vendor:sdl3` links
		`system:SDL3` and the dynamic loader finds it, so there is nothing to copy.

		Cheap to call repeatedly: it skips the copy when the destination already holds the
		same file.
	#>
	param(
		[Parameter(Mandatory)]
		[string]$Destination
	)

	if (-not $IsWindows) { return }

	$root = & odin root
	if ($LASTEXITCODE -ne 0 -or -not $root) {
		Write-Host 'odin root failed; cannot locate SDL3.dll.' -ForegroundColor Yellow
		return
	}

	$source = Join-Path $root.Trim() 'vendor/sdl3/SDL3.dll'
	if (-not (Test-Path $source)) {
		Write-Host "SDL3.dll not found at $source; SDL-linked binaries will not start." -ForegroundColor Yellow
		return
	}

	$target = Join-Path $Destination 'SDL3.dll'
	if (Test-Path $target) {
		$have = Get-Item $target
		$want = Get-Item $source
		if ($have.Length -eq $want.Length -and $have.LastWriteTimeUtc -ge $want.LastWriteTimeUtc) {
			return
		}
	}
	Copy-Item -Path $source -Destination $target -Force
}

function Select-OdinPackage {
	<#
	.SYNOPSIS
		Filters discovered packages down to the paths the caller named.
	.DESCRIPTION
		A path matches a package exactly (engine/platform) or as any directory
		above it (engine/core/containers selects every package underneath).
		Paths containing * or ? are treated as wildcards instead. Absolute paths
		and backslashes are accepted and normalized to repo-relative form.

		Emits nothing for a path that matches no package; the caller decides
		whether that is an error.
	#>
	param(
		[pscustomobject[]]$Packages,
		[string[]]$Paths
	)

	$normalized = foreach ($path in $Paths) {
		$p = $path.Replace('\', '/').TrimEnd('/')
		if ([System.IO.Path]::IsPathRooted($p)) {
			$p = [System.IO.Path]::GetRelativePath($RepoRoot, $p).Replace('\', '/').TrimEnd('/')
		}
		# ./engine/platform and .\engine\platform both land here as ./engine/platform.
		$p -replace '^\./', ''
	}

	$Packages | Where-Object {
		$pkg = $_
		foreach ($p in $normalized) {
			if ($p -match '[*?]') {
				if ($pkg.Path -like $p) { return $true }
			} elseif ($pkg.Path -eq $p -or $pkg.Path.StartsWith("$p/")) {
				return $true
			}
		}
		return $false
	}
}

function Write-Step {
	param([string]$Message)
	Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Summary {
	<#
	.SYNOPSIS
		Prints a pass/fail tally and returns the exit code the caller should use.
	#>
	param(
		[string]$Action,
		[int]$Total,
		[string[]]$Failed
	)
	Write-Host ''
	if ($Failed.Count -eq 0) {
		Write-Host "$Action ok: $Total/$Total packages" -ForegroundColor Green
		return 0
	}
	Write-Host "$Action failed: $($Failed.Count)/$Total packages" -ForegroundColor Red
	foreach ($name in $Failed) { Write-Host "  - $name" -ForegroundColor Red }
	return 1
}
