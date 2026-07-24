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

# Directories scanned for packages, relative to the repo root.
$SourceRoots = @('engine', 'examples', 'katas')

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
			[pscustomobject]@{
				Path         = [System.IO.Path]::GetRelativePath($RepoRoot, $_.Name).Replace('\', '/')
				Name         = Split-Path $_.Name -Leaf
				IsExecutable = [bool](Select-String -Path $files.FullName -Pattern '^\s*main\s*::\s*proc' -List -Quiet)
				HasTests     = [bool](@($files | Where-Object { $_.Name -like '*_test.odin' }).Count)
			}
		}
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
