#!/usr/bin/env pwsh
<#
.SYNOPSIS
	Formats and builds every Odin package in the repository.
.DESCRIPTION
	Runs odinfmt over the source tree, then compiles every package with the
	project's full vet/style flag set (see scripts/common.ps1). Packages that
	declare a `main` procedure are linked into build/; the rest are type-checked
	with `odin check -no-entry-point`.

	All packages are attempted even if an earlier one fails, so a single run
	reports every broken package. Exits non-zero if anything failed.
.PARAMETER NoFormat
	Skip the odinfmt pass and only compile.
.EXAMPLE
	./scripts/build.ps1
.EXAMPLE
	./scripts/build.ps1 -NoFormat
#>
[CmdletBinding()]
param(
	[switch]$NoFormat
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Collect native-command failures by hand instead of letting them throw.
$PSNativeCommandUseErrorActionPreference = $false

. (Join-Path $PSScriptRoot 'common.ps1')

function Invoke-Odinfmt {
	# odinfmt ships with ols (github.com/DanielGavin/ols); it is not part of the
	# Odin toolchain, so treat it as optional rather than failing the build.
	$odinfmt = Get-Command 'odinfmt' -CommandType Application -ErrorAction SilentlyContinue
	if (-not $odinfmt) {
		Write-Host 'odinfmt not found on PATH; skipping format pass.' -ForegroundColor Yellow
		Write-Host '  Install it from https://github.com/DanielGavin/ols (build.bat odinfmt).' -ForegroundColor Yellow
		return $true
	}

	$ok = $true
	foreach ($root in $SourceRoots) {
		if (-not (Test-Path $root)) { continue }
		Write-Step "odinfmt $root"
		& $odinfmt.Source -w $root
		if ($LASTEXITCODE -ne 0) {
			Write-Host "odinfmt failed on $root (exit $LASTEXITCODE)" -ForegroundColor Red
			$ok = $false
		}
	}
	return $ok
}

Push-Location $RepoRoot
try {
	$packages = @(Get-OdinPackage)
	if ($packages.Count -eq 0) {
		throw "No Odin packages found under: $($SourceRoots -join ', ')"
	}

	$formatOk = $true
	if (-not $NoFormat) {
		$formatOk = Invoke-Odinfmt
		Write-Host ''
	}

	New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

	$failed = @()
	foreach ($pkg in $packages) {
		if ($pkg.IsExecutable) {
			$out = "build/$($pkg.Name).exe"
			Write-Step "build $($pkg.Path) -> $out"
			& odin build $pkg.Path @OdinFlags @OdinCollections "-out:$out"
		} else {
			Write-Step "check $($pkg.Path)"
			& odin check $pkg.Path @OdinFlags @OdinCollections '-no-entry-point'
		}
		if ($LASTEXITCODE -ne 0) { $failed += $pkg.Path }
	}

	$code = Write-Summary -Action 'Build' -Total $packages.Count -Failed $failed
	if (-not $formatOk) {
		Write-Host 'odinfmt reported errors.' -ForegroundColor Red
		$code = 1
	}
	exit $code
} finally {
	Pop-Location
}
