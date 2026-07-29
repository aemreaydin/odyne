#!/usr/bin/env pwsh
<#
.SYNOPSIS
	Runs both tiers of the odyne test suite.
.DESCRIPTION
	Tier 1 — every package containing *_test.odin files, run with `odin test`.
	Tier 2 — every executable package under tests/: a HARNESS, built and then run.
	Those own `main` instead of using @(test) procedures because they need real
	windows, and `core:testing`'s runner dispatches onto a worker thread where SDL's
	video subsystem is unusable on macOS. Both tiers use the project's full vet/style
	flag set (see scripts/common.ps1), and both write binaries to build/tests/ so they
	stay out of the repo root.

	All packages are attempted even if an earlier one fails, so a single run
	reports every failing package. Exits non-zero if anything failed.
.PARAMETER Path
	Limits the run to one or more locations, relative to the repo root. A path
	matches a package exactly (engine/platform) or as any directory above it
	(engine/core/containers runs every package underneath). Paths containing
	* or ? are matched as wildcards. Omit to run everything.
.PARAMETER Threads
	Tier-1 test runner thread count. Defaults to 1: engine/platform shares package
	state and drives per-thread OS event queues, so its tests deadlock under the
	parallel runner. The suites are sub-millisecond, so running serially costs
	nothing worth reclaiming. Harnesses ignore this — they are single-threaded by
	construction.
.PARAMETER InProcess
	Runs harness cases in one process instead of one child process per case. Faster,
	but a crash then takes the whole run down with it rather than one case.
.EXAMPLE
	./scripts/test.ps1
.EXAMPLE
	./scripts/test.ps1 engine/platform
.EXAMPLE
	./scripts/test.ps1 tests/platform -InProcess
.EXAMPLE
	./scripts/test.ps1 -Path katas/* -Threads 8
#>
[CmdletBinding()]
param(
	[Parameter(Position = 0, ValueFromRemainingArguments = $true)]
	[string[]]$Path = @(),

	[ValidateRange(1, 256)]
	[int]$Threads = 1,

	[switch]$InProcess
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Collect native-command failures by hand instead of letting them throw.
$PSNativeCommandUseErrorActionPreference = $false

. (Join-Path $PSScriptRoot 'common.ps1')

Push-Location $RepoRoot
try {
	$packages = @(Get-OdinPackage | Where-Object { $_.HasTests -or $_.IsHarness })
	if ($packages.Count -eq 0) {
		Write-Host "No tests found under: $($SourceRoots -join ', ')" -ForegroundColor Yellow
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

		if ($pkg.IsHarness) {
			Write-Step "harness $($pkg.Path)"
			& odin build $pkg.Path @OdinFlags @OdinCollections @OdinLinkFlags "-out:$out"
			if ($LASTEXITCODE -ne 0) {
				$failed += $pkg.Path
				Write-Host ''
				continue
			}
			# The harness links SDL, and on Windows the loader wants the DLL beside the binary.
			Sync-SdlRuntime -Destination $testDir
			$harnessArgs = @()
			if ($InProcess) { $harnessArgs += '--in-process' }
			& $out @harnessArgs
			if ($LASTEXITCODE -ne 0) { $failed += $pkg.Path }
			Write-Host ''
			continue
		}

		Write-Step "test $($pkg.Path)"
		& odin test $pkg.Path @OdinFlags @OdinCollections @OdinLinkFlags "-out:$out" "-define:ODIN_TEST_THREADS=$Threads"
		if ($LASTEXITCODE -ne 0) { $failed += $pkg.Path }
		Write-Host ''
	}

	exit (Write-Summary -Action 'Tests' -Total $packages.Count -Failed $failed)
} finally {
	Pop-Location
}
