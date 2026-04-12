param(
    [string]$VivadoBin = "",
    [switch]$SkipCRef,
    [switch]$SkipHdl
)

$ErrorActionPreference = "Stop"

$implRoot = Split-Path -Parent $PSScriptRoot
$simRoot = Join-Path $implRoot "sources/sim"
$xsimRoot = Join-Path $implRoot "SHAKE256.sim/sim_1/behav/xsim"
$reportName = "compile_sim_status_{0}.md" -f (Get-Date -Format "yyyy-MM-dd_HHmmss")
$reportPath = Join-Path $implRoot (Join-Path "reports" $reportName)
$reportLines = New-Object System.Collections.Generic.List[string]

function Add-ReportLine {
    param([string]$Line)
    $script:reportLines.Add($Line)
}

function Resolve-VivadoBin {
    param([string]$Hint)

    if ($Hint -and (Test-Path (Join-Path $Hint "xvlog.bat"))) {
        return $Hint
    }

    $xvlogCmd = Get-Command xvlog -ErrorAction SilentlyContinue
    if ($xvlogCmd) {
        return (Split-Path -Parent $xvlogCmd.Source)
    }

    $amdDesignToolsRoot = "C:\AMDDesignTools"
    if (Test-Path $amdDesignToolsRoot) {
        $valid = @()

        foreach ($versionDir in (Get-ChildItem -Path $amdDesignToolsRoot -Directory -ErrorAction SilentlyContinue)) {
            $binPath = Join-Path (Join-Path $versionDir.FullName "Vivado") "bin"
            if (Test-Path (Join-Path $binPath "xvlog.bat")) {
                $parsedVersion = $null
                if (-not [version]::TryParse($versionDir.Name, [ref]$parsedVersion)) {
                    $parsedVersion = [version]"0.0"
                }

                $valid += [PSCustomObject]@{
                    Version = $parsedVersion
                    BinPath = $binPath
                }
            }
        }

        if ($valid.Count -gt 0) {
            return ($valid | Sort-Object Version)[-1].BinPath
        }
    }

    return $null
}

function Add-SectionHeader {
    param([string]$Text)
    Add-ReportLine ""
    Add-ReportLine "## $Text"
    Add-ReportLine ""
}

Add-ReportLine ("# Compile and Simulation Status ({0})" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Add-SectionHeader "Environment checks"

$gccCmd = Get-Command gcc -ErrorAction SilentlyContinue
if ($gccCmd) {
    Add-ReportLine "- GCC found: $($gccCmd.Source)"
} else {
    Add-ReportLine "- GCC found: NO"
}

$vivadoBinResolved = Resolve-VivadoBin -Hint $VivadoBin
if ($vivadoBinResolved) {
    Add-ReportLine "- Vivado bin resolved: $vivadoBinResolved"
} else {
    Add-ReportLine "- Vivado bin resolved: NO"
}

if (-not $SkipCRef) {
    Add-SectionHeader "C reference build/run"

    if (-not $gccCmd) {
        Add-ReportLine "- Build skipped: gcc not found in PATH"
    } else {
        Push-Location $simRoot
        try {
            $buildOut = & gcc -O2 -std=c11 -Wall -Wextra -o test_keccak_ref.exe test_keccak_ref.c ../../../PQClean/common/fips202.c -I../../../PQClean/common 2>&1
            $buildCode = $LASTEXITCODE

            if ($buildCode -ne 0) {
                Add-ReportLine "- Build status: FAIL (exit $buildCode)"
                Add-ReportLine ""
                Add-ReportLine "Build output:"
                Add-ReportLine ""
                foreach ($line in $buildOut) {
                    Add-ReportLine "  $line"
                }
            } else {
                Add-ReportLine "- Build status: PASS"
                $runOut = & .\test_keccak_ref.exe 2>&1
                $runCode = $LASTEXITCODE
                $runStatus = "FAIL"
                if ($runCode -eq 0) {
                    $runStatus = "PASS"
                }
                Add-ReportLine ("- Run status: {0} (exit {1})" -f $runStatus, $runCode)
                Add-ReportLine ""
                Add-ReportLine "Run output:"
                Add-ReportLine ""
                foreach ($line in $runOut) {
                    Add-ReportLine "  $line"
                }
            }
        } finally {
            Pop-Location
        }
    }
}

if (-not $SkipHdl) {
    Add-SectionHeader "HDL simulation attempt"

    if (-not (Test-Path $xsimRoot)) {
        Add-ReportLine "- xsim folder missing: $xsimRoot"
    } elseif (-not $vivadoBinResolved) {
        Add-ReportLine "- HDL sim status: BLOCKED (cannot locate Vivado bin with xvlog/xelab/xsim)"
    } else {
        if (-not (($env:Path -split ';') -contains $vivadoBinResolved)) {
            $env:Path = "$vivadoBinResolved;$env:Path"
        }

        Push-Location $xsimRoot
        try {
            Add-ReportLine "- Using Vivado bin: $vivadoBinResolved"

            $compileOut = & .\compile.bat 2>&1
            $compileCode = $LASTEXITCODE
            Add-ReportLine "- compile.bat exit: $compileCode"

            if ($compileCode -eq 0) {
                $elabOut = & .\elaborate.bat 2>&1
                $elabCode = $LASTEXITCODE
                Add-ReportLine "- elaborate.bat exit: $elabCode"

                if ($elabCode -eq 0) {
                    $simOut = & .\simulate.bat 2>&1
                    $simCode = $LASTEXITCODE
                    Add-ReportLine "- simulate.bat exit: $simCode"
                    Add-ReportLine ""
                    Add-ReportLine "simulate.bat output:"
                    Add-ReportLine ""
                    foreach ($line in $simOut) {
                        Add-ReportLine "  $line"
                    }
                } else {
                    Add-ReportLine ""
                    Add-ReportLine "elaborate.bat output:"
                    Add-ReportLine ""
                    foreach ($line in $elabOut) {
                        Add-ReportLine "  $line"
                    }
                }
            } else {
                Add-ReportLine ""
                Add-ReportLine "compile.bat output:"
                Add-ReportLine ""
                foreach ($line in $compileOut) {
                    Add-ReportLine "  $line"
                }
            }
        } finally {
            Pop-Location
        }
    }
}

$reportLines | Set-Content -Path $reportPath -Encoding ASCII

Write-Host "Report saved: $reportPath"
Write-Host "Done."
