# Lab 17 — Data Pipeline Engineering (Track 2) — Windows PowerShell Make Script
# Usage: .\make.ps1 <target> [options]
# Example: .\make.ps1 run
#          .\make.ps1 day -Day 2026-08-14
#          .\make.ps1 help

param(
    [string]$Target = "help",
    [string]$Day = "2026-08-12",
    [switch]$Help = $false
)

# Configuration
$VENV = ".venv"
$PY = Join-Path $VENV "Scripts\python.exe"
$DBT = (Resolve-Path (Join-Path $VENV "Scripts\dbt.exe")).Path
$env:DO_NOT_TRACK = "1"

# Helper functions
function Test-VenvExists {
    return Test-Path $VENV
}

function Test-DbtExists {
    if (Test-Path $DBT) { return $true }
    return $false
}

function Invoke-Cmd {
    param([string]$Command)
    Write-Host "→ $Command" -ForegroundColor Cyan
    Invoke-Expression $Command
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Command failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }
}

function Show-Help {
    $targets = @(
        @{ Name = "help"; Desc = "Show this help" },
        @{ Name = "setup"; Desc = "Create .venv + install the lite-path deps" },
        @{ Name = "setup-dbt"; Desc = "Add dbt-core + dbt-duckdb to .venv (dbt track)" },
        @{ Name = "run"; Desc = "Fresh build: reset Silver/Gold, backfill 08-10..08-16 from Bronze" },
        @{ Name = "day"; Desc = "One daily run on the existing warehouse, e.g. .\make.ps1 day -Day 2026-08-14" },
        @{ Name = "lateness"; Desc = "Measure event lateness (P50/P95/P99) from Bronze" },
        @{ Name = "rerun3"; Desc = "GRADING TEST: fresh build, re-run 2026-08-12 three times, compare checksums" },
        @{ Name = "verify"; Desc = "All pipeline contracts (18 checks)" },
        @{ Name = "test"; Desc = "pytest (unit tests + table contracts + extensions)" },
        @{ Name = "dbt"; Desc = "dbt track: land Bronze, dbt build" },
        @{ Name = "parity"; Desc = "dbt track: same Bronze in -> same checksum out (lite vs dbt)" },
        @{ Name = "bonus-llm"; Desc = "Bonus: LLM labelling step with hash cache + validation" },
        @{ Name = "flywheel"; Desc = "Extension (ungraded): agent traces -> eval set + DPO pairs" },
        @{ Name = "kg"; Desc = "Extension (ungraded): knowledge graph vs vector retrieval" },
        @{ Name = "docker-up"; Desc = "Bonus: the same daily run on real Airflow 3" },
        @{ Name = "clean"; Desc = "Remove venv and everything the pipeline built" }
    )

    Write-Host "`nUsage:`n  .\make.ps1 <target>`n" -ForegroundColor Green
    foreach ($target in $targets) {
        Write-Host ("  {0,-15} {1}" -f $target.Name, $target.Desc) -ForegroundColor Cyan
    }
    Write-Host ""
}

function Target-Setup {
    if (Test-VenvExists) {
        Write-Host "Virtual environment already exists at $VENV" -ForegroundColor Yellow
        return
    }
    Invoke-Cmd "python -m venv $VENV"
    Invoke-Cmd "&'$PY' -m pip -q install -r requirements.txt"
}

function Target-Setup-Dbt {
    if (-not (Test-VenvExists)) {
        Write-Host "Error: Virtual environment not found. Run 'make setup' first." -ForegroundColor Red
        exit 1
    }
    Invoke-Cmd "&'$PY' -m pip -q install -r requirements-dbt.txt"
}

function Target-Run {
    if (-not (Test-VenvExists)) {
        Write-Host "Error: Virtual environment not found. Run 'make setup' first." -ForegroundColor Red
        exit 1
    }
    Invoke-Cmd "&'$PY' main.py"
}

function Target-Day {
    if (-not (Test-VenvExists)) {
        Write-Host "Error: Virtual environment not found. Run 'make setup' first." -ForegroundColor Red
        exit 1
    }
    Invoke-Cmd "&'$PY' main.py --date $Day"
}

function Target-Lateness {
    if (-not (Test-VenvExists)) {
        Write-Host "Error: Virtual environment not found. Run 'make setup' first." -ForegroundColor Red
        exit 1
    }
    Invoke-Cmd "&'$PY' main.py --lateness"
}

function Target-Rerun3 {
    if (-not (Test-VenvExists)) {
        Write-Host "Error: Virtual environment not found. Run 'make setup' first." -ForegroundColor Red
        exit 1
    }
    Invoke-Cmd "&'$PY' -m scripts.rerun_check"
}

function Target-Verify {
    if (-not (Test-VenvExists)) {
        Write-Host "Error: Virtual environment not found. Run 'make setup' first." -ForegroundColor Red
        exit 1
    }
    Invoke-Cmd "&'$PY' -m scripts.verify"
}

function Target-Test {
    if (-not (Test-VenvExists)) {
        Write-Host "Error: Virtual environment not found. Run 'make setup' first." -ForegroundColor Red
        exit 1
    }
    Invoke-Cmd "&'$PY' -m pytest"
}

function Target-Dbt {
    if (-not (Test-VenvExists)) {
        Write-Host "Error: Virtual environment not found. Run 'make setup' first." -ForegroundColor Red
        exit 1
    }
    if (-not (Test-DbtExists)) {
        Write-Host "Error: dbt not found. Run 'make setup-dbt' first." -ForegroundColor Red
        exit 1
    }
    Invoke-Cmd "&'$PY' main.py --land-only" *> $null
    Push-Location "dbt_project"
    $env:DBT_PROFILES_DIR = "."
    Invoke-Cmd "&'$DBT' build --event-time-start 2026-08-10 --event-time-end 2026-08-17"
    Pop-Location
}

function Target-Parity {
    if (-not (Test-VenvExists)) {
        Write-Host "Error: Virtual environment not found. Run 'make setup' first." -ForegroundColor Red
        exit 1
    }
    Invoke-Cmd "&'$PY' -m scripts.parity"
}

function Target-Bonus-Llm {
    if (-not (Test-VenvExists)) {
        Write-Host "Error: Virtual environment not found. Run 'make setup' first." -ForegroundColor Red
        exit 1
    }
    Invoke-Cmd "&'$PY' -m scripts.bonus_llm"
}

function Target-Flywheel {
    if (-not (Test-VenvExists)) {
        Write-Host "Error: Virtual environment not found. Run 'make setup' first." -ForegroundColor Red
        exit 1
    }
    Invoke-Cmd "&'$PY' -m extensions.flywheel"
}

function Target-Kg {
    if (-not (Test-VenvExists)) {
        Write-Host "Error: Virtual environment not found. Run 'make setup' first." -ForegroundColor Red
        exit 1
    }
    Invoke-Cmd "&'$PY' -m extensions.kg_demo"
}

function Target-Docker-Up {
    Invoke-Cmd "docker compose -f docker/docker-compose.yml up"
}

function Target-Clean {
    Write-Host "Cleaning up venv, lake, warehouse, and cache files..." -ForegroundColor Yellow

    $itemsToRemove = @(
        $VENV,
        "lake",
        "warehouse.duckdb",
        "warehouse.duckdb.wal",
        "datasets",
        ".pytest_cache",
        "dbt_project\dbt.duckdb",
        "dbt_project\target",
        "dbt_project\logs"
    )

    foreach ($item in $itemsToRemove) {
        if (Test-Path $item) {
            Write-Host "  Removing: $item" -ForegroundColor Cyan
            Remove-Item -Path $item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Remove all __pycache__ directories
    Get-ChildItem -Path . -Name "__pycache__" -Recurse -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item -Path (Join-Path -Path (Split-Path $_) -ChildPath "__pycache__") -Recurse -Force -ErrorAction SilentlyContinue }

    Write-Host "Clean complete!" -ForegroundColor Green
}

# Main execution
switch ($Target.ToLower()) {
    "help"       { Show-Help }
    "setup"      { Target-Setup }
    "setup-dbt"  { Target-Setup-Dbt }
    "run"        { Target-Run }
    "day"        { Target-Day }
    "lateness"   { Target-Lateness }
    "rerun3"     { Target-Rerun3 }
    "verify"     { Target-Verify }
    "test"       { Target-Test }
    "dbt"        { Target-Dbt }
    "parity"     { Target-Parity }
    "bonus-llm"  { Target-Bonus-Llm }
    "flywheel"   { Target-Flywheel }
    "kg"         { Target-Kg }
    "docker-up"  { Target-Docker-Up }
    "clean"      { Target-Clean }
    default {
        Write-Host "Unknown target: $Target" -ForegroundColor Red
        Show-Help
        exit 1
    }
}
