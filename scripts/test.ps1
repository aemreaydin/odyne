#!/usr/bin/env pwsh
<#
.SYNOPSIS
	Runs the test suite of every Odin package that has one.
.DESCRIPTION
	Finds each package containing *_test.odin files and runs `odin test` on it
	with the project's full vet/style flag set (see scripts/common.ps1). Test
	binaries are written to build/tests/ so they stay out of the repo root.

	All packages are attempted even if an earlier one fails, so a single run
	reports every failing package. Exits non-zero if anything failed.
.PARAMETER Path
	Limits the run to one or more locations, relative to the repo root. A path
	matches a package exactly (engine/platform) or as any directory above it
	(engine/core/containers runs every package underneath). Paths containing
	* or ? are matched as wildcards. Omit to run everything.
.PARAMETER Threads
	Test runner thread count. Defaults to 1: engine/platform shares package state
	and drives Win32 message queues, which are per-thread, so its tests deadlock
	under the parallel runner. The suites are sub-millisecond, so running serially
	costs nothing worth reclaiming.
.EXAMPLE
	./scripts/test.ps1
.EXAMPLE
	./scripts/test.ps1 engine/platform
.EXAMPLE
	./scripts/test.ps1 engine/core/containers katas/pool
.EXAMPLE
	./scripts/test.ps1 -Path katas/* -Threads 8
#>
[CmdletBinding()]
param(
	[Parameter(Position = 0, ValueFromRemainingArguments = $true)]
	[string[]]$Path = @(),

	[ValidateRange(1, 256)]
	[int]$Threads = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Collect native-command failures by hand instead of letting them throw.
$PSNativeCommandUseErrorActionPreference = $false

. (Join-Path $PSScriptRoot 'common.ps1')

Push-Location $RepoRoot
try {
	$packages = @(Get-OdinPackage | Where-Object { $_.HasTests })
	if ($packages.Count -eq 0) {
		Write-Host "No packages with *_test.odin files found under: $($SourceRoots -join ', ')" -ForegroundColor Yellow
		exit 0
	}

	if ($Path.Count -gt 0) {
		$selected = @(Select-OdinPackage -Packages $packages -Paths $Path)
		if ($selected.Count -eq 0) {
			# A typo'd path silently running zero tests would read as success, so fail loudly.
			Write-Host "No tested package matches: $($Path -join ', ')" -ForegroundColor Red
			Write-Host 'Available:' -ForegroundColor Yellow
			foreach ($pkg in $packages) { Write-Host "  $($pkg.Path)" -ForegroundColor Yellow }
			exit 1
		}
		$packages = $selected
	}

	$testDir = Join-Path $BuildDir 'tests'
	New-Item -ItemType Directory -Force -Path $testDir | Out-Null

	$failed = @()
	foreach ($pkg in $packages) {
		# Package leaf names repeat across the tree (engine/.../handle_pool and
		# katas/handle_pool), so name the binary after the full path.
		$out = "build/tests/$($pkg.Path -replace '[/\\]', '_').exe"
		Write-Step "test $($pkg.Path)"
		& odin test $pkg.Path @OdinFlags @OdinCollections "-out:$out" "-define:ODIN_TEST_THREADS=$Threads"
		if ($LASTEXITCODE -ne 0) { $failed += $pkg.Path }
		Write-Host ''
	}

	exit (Write-Summary -Action 'Tests' -Total $packages.Count -Failed $failed)
} finally {
	Pop-Location
}
