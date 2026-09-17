#Requires -Version 5.1

$ErrorActionPreference = "Stop"

# ============================================================
# Codex Multi-Agent C# Refactoring Runner
# ============================================================

$ProjectRoot = $PSScriptRoot
$CodexHome = Join-Path $ProjectRoot ".codex"
$AgentsDirectory = Join-Path $CodexHome "agents"
$SampleRepository = $ProjectRoot
$TaskFile = Join-Path $ProjectRoot "REFACTORING-TASK.md"

$RunRoot = Join-Path $ProjectRoot ".codex-run"

$JsonLogFile = Join-Path $ProjectRoot "codex-run.jsonl"
$FinalResponseFile = Join-Path $ProjectRoot "codex-final-response.txt"
$ResultsFile = Join-Path $ProjectRoot "results.md"

$Model = "gpt-5.6-sol"
$ResetRepositoryBeforeRun = $true
$RunIndependentVerification = $true

$InputPricePerMillion = 4.00
$CachedInputPricePerMillion = 0.40
$OutputPricePerMillion = 20.00

$env:CODEX_HOME = $CodexHome

# ============================================================
# Helper Functions
# ============================================================

function Write-Section {
    param([string]$Message)

    Write-Host ""
    Write-Host "============================================================"
    Write-Host $Message
    Write-Host "============================================================"
}

function Write-SubSection {
    param([string]$Message)

    Write-Host ""
    Write-Host "------------------------------------------------------------"
    Write-Host $Message
    Write-Host "------------------------------------------------------------"
}

function Fail {
    param([string]$Message)

    Write-Host ""
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}

function Test-CommandExists {
    param([string]$CommandName)

    return $null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Format-Currency {
    param([double]$Value)

    return $Value.ToString(
        "0.0000",
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}

function Test-LocalCodexConfiguration {

    Write-Section "Validating Local Codex Configuration"

    if (-not (Test-Path -LiteralPath $CodexHome -PathType Container)) {
        Fail "Local CODEX_HOME directory was not found: $CodexHome"
    }

    $ConfigFile = Join-Path $CodexHome "config.toml"

    if (-not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) {
        Fail "config.toml was not found: $ConfigFile"
    }

    Write-Host "[OK] CODEX_HOME = $CodexHome" -ForegroundColor Green
    Write-Host "[OK] config.toml found:"
    Write-Host "     $ConfigFile"

    $Config = Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8

    if ([string]::IsNullOrWhiteSpace($Config)) {
        Fail "config.toml is empty."
    }

    $ModelProviderMatch = [regex]::Match(
        $Config,
        '(?m)^\s*model_provider\s*=\s*"([^"]+)"'
    )

    if ($ModelProviderMatch.Success) {
        Write-Host "[CONFIG] model_provider = $($ModelProviderMatch.Groups[1].Value)"
    }

    if ($Config -match '(?m)^\s*\[model_providers\.openai\]') {
        Fail "config.toml attempts to override the built-in 'openai' provider."
    }

    Write-Host "[OK] Local Codex configuration passed validation." -ForegroundColor Green
}

function Ensure-CodexInstalled {

    Write-Section "Validating Codex CLI"

    $CodexCommand = Get-Command codex -ErrorAction SilentlyContinue

    if ($null -ne $CodexCommand) {

        try {
            $Version = & $CodexCommand.Source --version 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Codex CLI: $Version" -ForegroundColor Green
            }
            else {
                Write-Host "[WARNING] Codex was found but version check returned $LASTEXITCODE." -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "[WARNING] Codex was found but version could not be determined." -ForegroundColor Yellow
        }

        return $CodexCommand.Source
    }

    Write-Host "[WARNING] Codex CLI was not found in PATH." -ForegroundColor Yellow
    Write-Host "[INFO] Installing Codex CLI using the official OpenAI installer..."

    if ($PSVersionTable.PSEdition -eq "Desktop") {
        try {
            [Net.ServicePointManager]::SecurityProtocol =
                [Net.ServicePointManager]::SecurityProtocol -bor
                [Net.SecurityProtocolType]::Tls12
        }
        catch {
            Write-Host "[WARNING] Could not explicitly enable TLS 1.2." -ForegroundColor Yellow
        }
    }

    $InstallerCommand = 'irm https://chatgpt.com/codex/install.ps1 | iex'

    try {
        & powershell.exe `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -Command $InstallerCommand

        $InstallerExitCode = $LASTEXITCODE
    }
    catch {
        Fail "Codex installation failed to start: $($_.Exception.Message)"
    }

    if ($InstallerExitCode -ne 0) {
        Fail "Codex installation failed. Installer exit code: $InstallerExitCode"
    }

    Write-Host "[OK] Codex installer completed." -ForegroundColor Green

    $MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")

    if ($null -eq $MachinePath) { $MachinePath = "" }
    if ($null -eq $UserPath) { $UserPath = "" }

    $env:Path = "$MachinePath;$UserPath"

    $PossiblePaths = @(
        (Join-Path $env:USERPROFILE ".codex\bin\codex.exe"),
        (Join-Path $env:USERPROFILE ".local\bin\codex.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\codex\codex.exe")
    )

    foreach ($Path in $PossiblePaths) {

        if (Test-Path -LiteralPath $Path -PathType Leaf) {

            $Directory = Split-Path -Path $Path -Parent

            if ($env:Path -notlike "*$Directory*") {
                $env:Path = "$Directory;$env:Path"
            }

            break
        }
    }

    $CodexCommand = Get-Command codex -ErrorAction SilentlyContinue

    if ($null -eq $CodexCommand) {
        Fail @"
Codex was installed but is not available in the current PowerShell PATH.

Close and reopen PowerShell, then run:

    codex --version

and rerun this script.
"@
    }

    try {
        $Version = & $CodexCommand.Source --version 2>&1
        Write-Host "[OK] Codex CLI installed: $Version" -ForegroundColor Green
    }
    catch {
        Write-Host "[OK] Codex CLI installed at: $($CodexCommand.Source)" -ForegroundColor Green
    }

    return $CodexCommand.Source
}

function Remove-PreviousRunFiles {

    Write-Section "Cleaning Previous Run Files"

    $Files = @(
        $JsonLogFile,
        $FinalResponseFile,
        $ResultsFile
    )

    foreach ($File in $Files) {

        if (Test-Path -LiteralPath $File) {

            try {
                Remove-Item -LiteralPath $File -Force -ErrorAction Stop
                Write-Host "[DELETED] $File" -ForegroundColor Yellow
            }
            catch {
                Fail "Could not delete previous run file '$File': $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "[OK] Not found: $File" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    Write-Host "[OK] Previous run files cleaned." -ForegroundColor Green
}

function Stop-ProcessesUsingRepository {
    param([Parameter(Mandatory)][string]$RepositoryPath)

    Write-Host "[RESET] Checking for processes using sample-repository..." -ForegroundColor Gray

    $FullPath = [System.IO.Path]::GetFullPath($RepositoryPath).TrimEnd('\')

    $ProcessNames = @(
        "codex",
        "dotnet",
        "testhost",
        "MSBuild",
        "VBCSCompiler",
        "vstest.console",
        "node"
    )

    try {
        $Processes = Get-CimInstance Win32_Process -ErrorAction Stop |
            Where-Object {
                ($_.Name -replace '\.exe$','') -in $ProcessNames -and
                -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
                $_.CommandLine.IndexOf(
                    $FullPath,
                    [System.StringComparison]::OrdinalIgnoreCase
                ) -ge 0
            }
    }
    catch {
        Write-Host "[WARNING] Could not inspect running processes: $($_.Exception.Message)" -ForegroundColor Yellow
        return
    }

    foreach ($ProcessInfo in $Processes) {

        try {
            $Process = Get-Process -Id $ProcessInfo.ProcessId -ErrorAction SilentlyContinue

            if ($null -eq $Process) {
                continue
            }

            Write-Host "[RESET] Stopping $($ProcessInfo.Name) PID $($ProcessInfo.ProcessId)..." -ForegroundColor Yellow

            Stop-Process `
                -Id $ProcessInfo.ProcessId `
                -Force `
                -ErrorAction Stop
        }
        catch {
            Write-Host "[WARNING] Could not stop PID $($ProcessInfo.ProcessId): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Start-Sleep -Milliseconds 750
}

function Reset-RepositoryToCommittedState {
    Write-Host ""
    Write-Host "Resetting Working Repository (Baseline Copy)" -ForegroundColor Cyan

    $BaselineRepository = Join-Path $ProjectRoot "original-repository"
    $SampleRepository = Join-Path $ProjectRoot "sample-repository"

    if (-not (Test-Path -LiteralPath $BaselineRepository -PathType Container)) {
        # First-run bootstrap: if the ZIP contains a sample-repository but no
        # original-repository, preserve that sample as the immutable baseline.
        # This removes the Git dependency and means the exercise works immediately
        # after extraction.
        if (Test-Path -LiteralPath $SampleRepository -PathType Container) {
            Write-Host "[INIT] original-repository not found." -ForegroundColor Yellow
            Write-Host "[INIT] Creating pristine baseline from sample-repository..." -ForegroundColor DarkGray

            New-Item -ItemType Directory -Path $BaselineRepository -Force | Out-Null

            $robocopyInit = Get-Command robocopy.exe -ErrorAction SilentlyContinue
            if ($robocopyInit) {
                & $robocopyInit.Source $SampleRepository $BaselineRepository /E /R:2 /W:1 /XJ /NFL /NDL /NJH /NJS
                $initRc = $LASTEXITCODE
                if ($initRc -ge 8) {
                    throw "Initial baseline copy failed with Robocopy exit code $initRc."
                }
            }
            else {
                Copy-Item -LiteralPath (Join-Path $SampleRepository "*") `
                    -Destination $BaselineRepository -Recurse -Force -ErrorAction Stop
            }

            Write-Host "[OK] original-repository baseline created." -ForegroundColor Green
        }
        else {
            Write-Host "[ERROR] Neither original-repository nor sample-repository exists." -ForegroundColor Red
            Write-Host "        The exercise ZIP must contain the initial sample-repository." -ForegroundColor Yellow
            throw "Missing exercise baseline and sample repository."
        }
    }

    $baselineFull = [IO.Path]::GetFullPath($BaselineRepository).TrimEnd('\')
    $sampleFull = [IO.Path]::GetFullPath($SampleRepository).TrimEnd('\')

    if ($baselineFull -eq $sampleFull) {
        throw "Safety check failed: original-repository and sample-repository must be different directories."
    }

    # The baseline is immutable. The sample directory is disposable.
    if (Test-Path -LiteralPath $SampleRepository) {
        Write-Host "[RESET] Removing previous sample-repository..." -ForegroundColor DarkGray

        Get-Process -Name "dotnet","codex" -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue

        Remove-Item -LiteralPath $SampleRepository -Recurse -Force -ErrorAction Stop
    }

    Write-Host "[RESET] Copying pristine baseline..." -ForegroundColor DarkGray
    New-Item -ItemType Directory -Path $SampleRepository -Force | Out-Null

    $robocopy = Get-Command robocopy.exe -ErrorAction SilentlyContinue
    if ($robocopy) {
        & $robocopy.Source $BaselineRepository $SampleRepository /E /R:2 /W:1 /XJ /NFL /NDL /NJH /NJS
        $rc = $LASTEXITCODE
        if ($rc -ge 8) {
            throw "Robocopy failed with exit code $rc."
        }
    }
    else {
        Copy-Item -LiteralPath (Join-Path $BaselineRepository "*") `
            -Destination $SampleRepository -Recurse -Force -ErrorAction Stop
    }

    # Always start the working copy without previous build output.
    Get-ChildItem -LiteralPath $SampleRepository -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @("bin", "obj") } |
        Sort-Object FullName -Descending |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    $requiredProject = Join-Path $SampleRepository "src\OrderProcessing\OrderProcessing.csproj"
    $requiredSolution = Join-Path $SampleRepository "OrderProcessing.sln"

    if (-not (Test-Path -LiteralPath $requiredProject -PathType Leaf)) {
        throw "Reset completed but the expected project was not found: $requiredProject"
    }

    if (-not (Test-Path -LiteralPath $requiredSolution -PathType Leaf)) {
        throw "Reset completed but the expected solution was not found: $requiredSolution"
    }

    Write-Host "[OK] sample-repository restored from original-repository." -ForegroundColor Green
}

function Test-PredefinedAgents {

    Write-Section "Validating Predefined Agents"

    $RequiredAgents = @(
        "business-analyst.toml",
        "csharp-architect.toml",
        "test-engineer.toml",
        "devops-reviewer.toml"
    )

    if (-not (Test-Path -LiteralPath $AgentsDirectory -PathType Container)) {
        Fail "Agents directory was not found: $AgentsDirectory"
    }

    foreach ($Agent in $RequiredAgents) {

        $Path = Join-Path $AgentsDirectory $Agent

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Fail "Required agent was not found: $Path"
        }

        Write-Host "[OK] $Agent" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "[OK] All predefined agents are available." -ForegroundColor Green
}

function Invoke-DotNet {
    param(
        [Parameter(Mandatory)][string]$Arguments,
        [Parameter(Mandatory)][string]$LogFile
    )

    Write-Host ""
    Write-Host "[DOTNET] dotnet $Arguments" -ForegroundColor Cyan

    $Psi = New-Object System.Diagnostics.ProcessStartInfo
    $Psi.FileName = "dotnet.exe"
    $Psi.Arguments = $Arguments
    $Psi.WorkingDirectory = $SampleRepository
    $Psi.UseShellExecute = $false
    $Psi.CreateNoWindow = $true
    $Psi.RedirectStandardOutput = $true
    $Psi.RedirectStandardError = $true

    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $Psi

    try {

        $null = $Process.Start()

        $StdOutTask = $Process.StandardOutput.ReadToEndAsync()
        $StdErrTask = $Process.StandardError.ReadToEndAsync()

        $Process.WaitForExit()

        $StdOut = $StdOutTask.Result
        $StdErr = $StdErrTask.Result

        $Combined = @(
            $StdOut
            $StdErr
        ) -join [Environment]::NewLine

        Set-Content -LiteralPath $LogFile -Value $Combined -Encoding UTF8

        if (-not [string]::IsNullOrWhiteSpace($StdOut)) {
            Write-Host $StdOut.TrimEnd()
        }

        if (-not [string]::IsNullOrWhiteSpace($StdErr)) {
            Write-Host $StdErr.TrimEnd() -ForegroundColor Yellow
        }

        return @{
            ExitCode = $Process.ExitCode
            Output = $Combined
        }
    }
    finally {
        $Process.Dispose()
    }
}

function Read-FileTail {
    param(
        [string]$Path,
        [long]$Offset
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{
            Text = ""
            Offset = $Offset
        }
    }

    try {

        $Stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )

        try {

            if ($Stream.Length -lt $Offset) {
                $Offset = 0
            }

            $Stream.Position = $Offset

            $Reader = New-Object System.IO.StreamReader(
                $Stream,
                [System.Text.Encoding]::UTF8,
                $true
            )

            try {
                $Text = $Reader.ReadToEnd()
                $NewOffset = $Stream.Position
            }
            finally {
                $Reader.Dispose()
            }
        }
        finally {
            $Stream.Dispose()
        }

        return @{
            Text = $Text
            Offset = $NewOffset
        }
    }
    catch {
        return @{
            Text = ""
            Offset = $Offset
        }
    }
}

function Get-CodexUsage {
    param([string]$Path)

    $Result = @{
        InputTokens = 0L
        CachedInputTokens = 0L
        OutputTokens = 0L
        ReasoningOutputTokens = 0L
        TotalTokens = 0L
        ThreadId = ""
        TurnCount = 0
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return $Result
    }

    foreach ($Line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {

        if ([string]::IsNullOrWhiteSpace($Line)) {
            continue
        }

        try {
            $Event = $Line | ConvertFrom-Json
        }
        catch {
            continue
        }

        if (
            [string]::IsNullOrWhiteSpace($Result.ThreadId) -and
            $null -ne $Event.thread_id
        ) {
            $Result.ThreadId = [string]$Event.thread_id
        }

        if ($Event.type -eq "turn.started") {
            $Result.TurnCount++
        }

        $Usage = $null

        if ($null -ne $Event.usage) {
            $Usage = $Event.usage
        }
        elseif (
            $null -ne $Event.turn -and
            $null -ne $Event.turn.usage
        ) {
            $Usage = $Event.turn.usage
        }

        if ($null -eq $Usage) {
            continue
        }

        if ($null -ne $Usage.input_tokens) {
            $Result.InputTokens += [long]$Usage.input_tokens
        }

        if ($null -ne $Usage.cached_input_tokens) {
            $Result.CachedInputTokens += [long]$Usage.cached_input_tokens
        }

        if ($null -ne $Usage.output_tokens) {
            $Result.OutputTokens += [long]$Usage.output_tokens
        }

        if ($null -ne $Usage.reasoning_output_tokens) {
            $Result.ReasoningOutputTokens += [long]$Usage.reasoning_output_tokens
        }

        if ($null -ne $Usage.total_tokens) {
            $Result.TotalTokens = [long]$Usage.total_tokens
        }
    }

    if ($Result.TotalTokens -eq 0) {
        $Result.TotalTokens =
            $Result.InputTokens +
            $Result.OutputTokens
    }

    return $Result
}

# ============================================================
# Startup
# ============================================================

Clear-Host

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Codex Refactoring Exercise Starting" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Project Root : $ProjectRoot"
Write-Host "CODEX_HOME   : $CodexHome"
Write-Host "Model        : $Model"
Write-Host ""

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    Fail "Project root does not exist."
}

if (-not (Test-Path -LiteralPath $SampleRepository -PathType Container)) {
    Fail "sample-repository does not exist: $SampleRepository"
}

if (-not (Test-Path -LiteralPath $TaskFile -PathType Leaf)) {
    Fail "REFACTORING-TASK.md does not exist."
}

if (-not (Test-CommandExists "git")) {
    Fail "Git is not installed or is not available in PATH."
}

if (-not (Test-CommandExists "dotnet")) {
    Fail ".NET SDK is not installed or is not available in PATH."
}

# ============================================================
# Clean previous top-level compatibility files
# ============================================================

Remove-PreviousRunFiles

# ============================================================
# API Key
# ============================================================

Write-Section "Validating API Authentication"

if ([string]::IsNullOrWhiteSpace($env:CODEX_API_KEY)) {

    if ([string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) {
        Fail "Neither CODEX_API_KEY nor OPENAI_API_KEY is configured."
    }

    $env:CODEX_API_KEY = $env:OPENAI_API_KEY
}

Write-Host "[OK] API key detected." -ForegroundColor Green

# ============================================================
# Codex
# ============================================================

$CodexExecutable = Ensure-CodexInstalled

Test-LocalCodexConfiguration

# ============================================================
# Task Specification
# ============================================================

Write-Section "Validating Task Specification"

$TaskInfoBefore = Get-Item -LiteralPath $TaskFile

$TaskOriginalLength = $TaskInfoBefore.Length
$TaskOriginalLastWriteTime = $TaskInfoBefore.LastWriteTimeUtc

$TaskSpecification = Get-Content `
    -LiteralPath $TaskFile `
    -Raw `
    -Encoding UTF8

if ([string]::IsNullOrWhiteSpace($TaskSpecification)) {
    Fail "REFACTORING-TASK.md is empty."
}

Write-Host "[OK] Task file found:"
Write-Host "     $TaskFile"
Write-Host "[OK] Task specification loaded." -ForegroundColor Green

# ============================================================
# Agents
# ============================================================

Test-PredefinedAgents

# ============================================================
# Git Reset
# ============================================================

if ($ResetRepositoryBeforeRun) {
    $StartingCommit = Reset-RepositoryToCommittedState `
        -RepositoryPath $SampleRepository
}
else {

    Push-Location $SampleRepository

    try {
        $StartingCommit = (git rev-parse HEAD 2>&1) -join ""

        if ($LASTEXITCODE -ne 0) {
            Fail "Unable to determine current Git commit."
        }
    }
    finally {
        Pop-Location
    }

    Write-Host "[INFO] Repository reset disabled." -ForegroundColor Yellow
}

# Verify task file after reset.
$TaskInfoAfterReset = Get-Item -LiteralPath $TaskFile

if (
    $TaskInfoAfterReset.Length -ne $TaskOriginalLength -or
    $TaskInfoAfterReset.LastWriteTimeUtc -ne $TaskOriginalLastWriteTime
) {
    Fail "REFACTORING-TASK.md changed during repository reset."
}

Write-Host "[OK] REFACTORING-TASK.md remains unchanged." -ForegroundColor Green

# ============================================================
# Build Multi-Agent Prompt
# ============================================================

Write-Section "Building Multi-Agent Prompt"

$Prompt = @"
You are the lead/orchestrator for a multi-agent C# refactoring exercise.

WORKING REPOSITORY:
$SampleRepository

TASK SPECIFICATION:
------------------------------------------------------------

$TaskSpecification

------------------------------------------------------------

You MUST use all four predefined specialist agents:

1. business-analyst
2. csharp-architect
3. test-engineer
4. devops-reviewer

Their configurations are located in:

$AgentsDirectory

Do not solve this as a single-agent task.

============================================================
REQUIRED WORKFLOW
============================================================

1. Inspect the repository and understand the existing implementation.

2. Use the business-analyst to review:
   - requirements
   - business rules
   - acceptance criteria
   - ambiguity
   - validation
   - edge cases
   - business risks

3. Use the test-engineer to:
   - identify missing tests
   - preserve existing observable behaviour
   - add/update automated tests
   - identify boundary conditions
   - identify performance risks
   - create BenchmarkDotNet benchmarks for meaningful new or
     materially refactored code where performance measurement is useful
   - use representative small, medium and large inputs where appropriate
   - measure execution time and allocations where useful
   - keep benchmarks separate from ordinary unit/integration tests
   - ensure benchmarks are deterministic and do not change production behaviour
   - run benchmarks in Release configuration
   - avoid creating meaningless benchmarks for trivial methods

4. Use the csharp-architect to review and implement:
   - architecture
   - SOLID
   - separation of concerns
   - dependency injection
   - testability
   - maintainability
   - performance
   - security

5. Implement the required refactoring and functionality.

6. Use the test-engineer again after implementation to review:
   - unit test coverage
   - integration coverage
   - regression coverage
   - edge cases
   - benchmark coverage
   - performance risks
   - allocation risks
   - scaling risks

7. Use the devops-reviewer to review:
   - build reproducibility
   - test execution
   - benchmark execution
   - dependency management
   - security
   - CI/CD readiness
   - release readiness
   - maintainability

8. Fix issues found by the specialists.

9. Run:
   dotnet restore
   dotnet build --configuration Release --no-restore
   dotnet test --configuration Release --no-build --no-restore

10. If benchmark projects were created, run their benchmarks in Release
    configuration and report the results. Do not substitute benchmark
    execution for the normal test suite.

11. Re-run tests after any fixes.

============================================================
REPOSITORY SAFETY
============================================================

Only modify files inside:

$SampleRepository

Do NOT modify:

$TaskFile

Do NOT modify the Git history.

Do NOT modify files outside the working repository.

Do NOT create Docker, Kubernetes, cloud infrastructure, databases,
or unrelated infrastructure.

Do NOT invent business rules.

Preserve existing observable behaviour unless the task specification
explicitly requires a change.

============================================================
FINAL RESPONSE
============================================================

Return a concise implementation report containing:

## Business Analyst
Findings and contribution.

## C# Architect
Architecture findings and contribution.

## Test Engineer
Test findings, tests created/changed, coverage gaps, and benchmark
tests created.

## DevOps Reviewer
Findings and contribution.

## Consolidated Findings
Important issues identified and resolved.

## Refactoring Implemented
Summary of implementation changes.

## Tests
Tests added/changed and results.

## Benchmarks
Benchmark project, benchmark cases, configuration, and results.
If no benchmark was appropriate for a particular change, explain why.

## Build Result
Actual build command and observed result.

## Test Result
Actual test command and observed result.

## Assumptions
Any assumptions made.

## Unresolved Questions
Anything requiring clarification.

## Remaining Risks
Known remaining technical or performance risks.

Do not claim that a command, benchmark, specialist review, or test was
performed unless it was actually performed.
"@

$ExecutionDirectory = Join-Path `
    (Join-Path $RunRoot (Get-Date -Format "yyyyMMdd-HHmmss")) `
    ""

New-Item -ItemType Directory -Path $ExecutionDirectory -Force | Out-Null

$PromptFile = Join-Path $ExecutionDirectory "prompt.txt"
$StdOutFile = Join-Path $ExecutionDirectory "stdout.jsonl"
$StdErrFile = Join-Path $ExecutionDirectory "stderr.log"
$LastMessageFile = Join-Path $ExecutionDirectory "final-response.txt"
$ExitCodeFile = Join-Path $ExecutionDirectory "exit-code.txt"
$RunnerCmdFile = Join-Path $ExecutionDirectory "run-codex.cmd"

Set-Content -LiteralPath $PromptFile -Value $Prompt -Encoding UTF8

Write-Host "[OK] Multi-agent prompt created." -ForegroundColor Green

# ============================================================
# Execute Codex
# ============================================================

Write-Section "Running Codex Refactoring"

Write-Host "Working directory: $SampleRepository"
Write-Host "Model            : $Model"
Write-Host "CODEX_HOME       : $CodexHome"
Write-Host "Prompt transport : stdin"
Write-Host ""
Write-Host "[CODEX] Starting..."
Write-Host "[CODEX] Logs: $ExecutionDirectory"
Write-Host ""

$StartTime = Get-Date

$CodexPathCmd = $CodexExecutable.Replace('"', '""')
$PromptPathCmd = $PromptFile.Replace('"', '""')
$StdOutPathCmd = $StdOutFile.Replace('"', '""')
$StdErrPathCmd = $StdErrFile.Replace('"', '""')
$LastMessagePathCmd = $LastMessageFile.Replace('"', '""')
$ExitCodePathCmd = $ExitCodeFile.Replace('"', '""')

$CmdContent = @"
@echo off
setlocal
set "CODEX_HOME=$CodexHome"
"$CodexPathCmd" exec --model "$Model" --sandbox danger-full-access --skip-git-repo-check --json --output-last-message "$LastMessagePathCmd" - < "$PromptPathCmd" > "$StdOutPathCmd" 2> "$StdErrPathCmd"
set "CODEX_EXIT=%ERRORLEVEL%"
echo %CODEX_EXIT% > "$ExitCodePathCmd"
exit /b %CODEX_EXIT%
"@

Set-Content -LiteralPath $RunnerCmdFile -Value $CmdContent -Encoding ASCII

$ProcessStartInfo = New-Object System.Diagnostics.ProcessStartInfo
$ProcessStartInfo.FileName = "cmd.exe"
$ProcessStartInfo.Arguments = "/d /c `"$RunnerCmdFile`""
$ProcessStartInfo.WorkingDirectory = $SampleRepository
$ProcessStartInfo.UseShellExecute = $false
$ProcessStartInfo.CreateNoWindow = $true
$ProcessStartInfo.Environment["CODEX_HOME"] = $CodexHome
$ProcessStartInfo.Environment["CODEX_API_KEY"] = $env:CODEX_API_KEY

$CodexProcess = New-Object System.Diagnostics.Process
$CodexProcess.StartInfo = $ProcessStartInfo

$RunnerPidFile = Join-Path $ProjectRoot ".codex-run.pid"
Set-Content -LiteralPath $RunnerPidFile -Value $PID -Encoding ASCII

$StdOutOffset = 0L
$StdErrOffset = 0L
$LastHeartbeat = Get-Date
$CodexExitCode = 1

try {

    $null = $CodexProcess.Start()

    Write-Host "[CODEX] Process started." -ForegroundColor Green

    while (-not $CodexProcess.HasExited) {

        Start-Sleep -Seconds 1

        $OutResult = Read-FileTail `
            -Path $StdOutFile `
            -Offset $StdOutOffset

        $StdOutOffset = $OutResult.Offset

        if (-not [string]::IsNullOrWhiteSpace($OutResult.Text)) {

            foreach ($Line in ($OutResult.Text -split "`r?`n")) {

                if ([string]::IsNullOrWhiteSpace($Line)) {
                    continue
                }

                try {

                    $Event = $Line | ConvertFrom-Json

                    switch ($Event.type) {

                        "thread.started" {
                            Write-Host "[CODEX] Thread started: $($Event.thread_id)" -ForegroundColor DarkCyan
                        }

                        "turn.started" {
                            Write-Host "[CODEX] Turn started." -ForegroundColor DarkCyan
                        }

                        "turn.completed" {
                            Write-Host "[CODEX] Turn completed." -ForegroundColor DarkCyan
                        }

                        "item.started" {
                            if ($null -ne $Event.item) {
                                Write-Host "[CODEX] Started: $($Event.item.type)" -ForegroundColor Gray
                            }
                        }

                        "item.completed" {
                            if ($null -ne $Event.item) {
                                Write-Host "[CODEX] Completed: $($Event.item.type)" -ForegroundColor Gray
                            }
                        }

                        "error" {
                            Write-Host "[CODEX ERROR] $($Event.message)" -ForegroundColor Red
                        }
                    }
                }
                catch {
                    Write-Host "[CODEX] $Line"
                }
            }
        }

        $ErrResult = Read-FileTail `
            -Path $StdErrFile `
            -Offset $StdErrOffset

        $StdErrOffset = $ErrResult.Offset

        if (-not [string]::IsNullOrWhiteSpace($ErrResult.Text)) {

            foreach ($Line in ($ErrResult.Text -split "`r?`n")) {

                if (-not [string]::IsNullOrWhiteSpace($Line)) {
                    Write-Host "[CODEX STDERR] $Line" -ForegroundColor Yellow
                }
            }
        }

        $Now = Get-Date

        if (($Now - $LastHeartbeat).TotalSeconds -ge 15) {

            $Elapsed = $Now - $StartTime

            $OutSize = if (Test-Path -LiteralPath $StdOutFile) {
                (Get-Item -LiteralPath $StdOutFile).Length
            }
            else {
                0
            }

            $ErrSize = if (Test-Path -LiteralPath $StdErrFile) {
                (Get-Item -LiteralPath $StdErrFile).Length
            }
            else {
                0
            }

            Write-Host (
                "[RUNNER] Codex still running | Elapsed: {0} | stdout: {1:N0} bytes | stderr: {2:N0} bytes" -f
                $Elapsed.ToString("hh\:mm\:ss"),
                $OutSize,
                $ErrSize
            ) -ForegroundColor DarkCyan

            $LastHeartbeat = $Now
        }
    }

    $CodexProcess.WaitForExit()
    $CodexExitCode = $CodexProcess.ExitCode
}
catch {
    Write-Host "[ERROR] Codex execution failed: $($_.Exception.Message)" -ForegroundColor Red
    $CodexExitCode = 1
}
finally {

    if ($null -ne $CodexProcess) {
        $CodexProcess.Dispose()
    }

    if (Test-Path -LiteralPath $RunnerPidFile) {
        Remove-Item -LiteralPath $RunnerPidFile -Force -ErrorAction SilentlyContinue
    }
}

$EndTime = Get-Date
$Duration = $EndTime - $StartTime

Write-Host ""
Write-Host "[CODEX] Process completed." -ForegroundColor Cyan
Write-Host "Exit code: $CodexExitCode"
Write-Host "Duration : $($Duration.ToString("hh\:mm\:ss"))"

# Copy main JSONL/final response to compatibility paths.
if (Test-Path -LiteralPath $StdOutFile) {
    Copy-Item -LiteralPath $StdOutFile -Destination $JsonLogFile -Force
}

if (Test-Path -LiteralPath $LastMessageFile) {
    Copy-Item -LiteralPath $LastMessageFile -Destination $FinalResponseFile -Force
}

# ============================================================
# Independent Verification
# ============================================================

$RestoreExitCode = $null
$BuildExitCode = $null
$TestExitCode = $null

$BuildStatus = "NOT RUN"
$TestStatus = "NOT RUN"

if ($RunIndependentVerification) {

    Write-Section "Independent Build and Test Verification"

    $RestoreLog = Join-Path $ExecutionDirectory "dotnet-restore.log"
    $BuildLog = Join-Path $ExecutionDirectory "dotnet-build.log"
    $TestLog = Join-Path $ExecutionDirectory "dotnet-test.log"

    $RestoreResult = Invoke-DotNet `
        -Arguments "restore" `
        -LogFile $RestoreLog

    $RestoreExitCode = $RestoreResult.ExitCode

    if ($RestoreExitCode -eq 0) {

        $BuildResult = Invoke-DotNet `
            -Arguments "build --configuration Release --no-restore" `
            -LogFile $BuildLog

        $BuildExitCode = $BuildResult.ExitCode

        if ($BuildExitCode -eq 0) {
            $BuildStatus = "SUCCESS"
        }
        else {
            $BuildStatus = "FAILED"
        }
    }
    else {
        $BuildStatus = "NOT RUN - RESTORE FAILED"
    }

    if ($BuildExitCode -eq 0) {

        $TestResult = Invoke-DotNet `
            -Arguments "test --configuration Release --no-build --no-restore" `
            -LogFile $TestLog

        $TestExitCode = $TestResult.ExitCode

        if ($TestExitCode -eq 0) {
            $TestStatus = "SUCCESS"
        }
        else {
            $TestStatus = "FAILED"
        }
    }
    else {
        $TestStatus = "NOT RUN - BUILD FAILED"
    }
}

# ============================================================
# Task File Protection Verification
# ============================================================

$TaskInfoFinal = Get-Item -LiteralPath $TaskFile

$TaskFileUnchanged = (
    $TaskInfoFinal.Length -eq $TaskOriginalLength -and
    $TaskInfoFinal.LastWriteTimeUtc -eq $TaskOriginalLastWriteTime
)

if (-not $TaskFileUnchanged) {
    Fail "REFACTORING-TASK.md was modified during execution."
}

Write-Host "[OK] REFACTORING-TASK.md remains unchanged." -ForegroundColor Green

# ============================================================
# Usage and Cost
# ============================================================

Write-Section "Codex Usage and Cost"

$Usage = Get-CodexUsage -Path $StdOutFile

$UncachedInputTokens = [Math]::Max(
    0,
    $Usage.InputTokens - $Usage.CachedInputTokens
)

$InputCost = (
    $UncachedInputTokens / 1000000.0
) * $InputPricePerMillion

$CachedInputCost = (
    $Usage.CachedInputTokens / 1000000.0
) * $CachedInputPricePerMillion

$OutputCost = (
    $Usage.OutputTokens / 1000000.0
) * $OutputPricePerMillion

$TotalEstimatedCost =
    $InputCost +
    $CachedInputCost +
    $OutputCost

Write-Host "Input Tokens          : $($Usage.InputTokens.ToString("N0"))"
Write-Host "Cached Input Tokens   : $($Usage.CachedInputTokens.ToString("N0"))"
Write-Host "Uncached Input Tokens : $($UncachedInputTokens.ToString("N0"))"
Write-Host "Output Tokens         : $($Usage.OutputTokens.ToString("N0"))"
Write-Host "Reasoning Tokens      : $($Usage.ReasoningOutputTokens.ToString("N0"))"
Write-Host "Total Tokens          : $($Usage.TotalTokens.ToString("N0"))"
Write-Host ""
Write-Host "Estimated Cost:"
Write-Host "  Uncached Input : `$$((Format-Currency $InputCost))"
Write-Host "  Cached Input   : `$$((Format-Currency $CachedInputCost))"
Write-Host "  Output         : `$$((Format-Currency $OutputCost))"
Write-Host "  TOTAL          : `$$((Format-Currency $TotalEstimatedCost))" -ForegroundColor Cyan

# ============================================================
# Final Response / Results
# ============================================================

$FinalResponseForResults = ""

if (Test-Path -LiteralPath $FinalResponseFile) {
    $FinalResponseForResults = Get-Content `
        -LiteralPath $FinalResponseFile `
        -Raw `
        -Encoding UTF8
}

$RunStatus = "SUCCESS"

if ($CodexExitCode -ne 0) {
    $RunStatus = "FAILED"
}

if (
    $RunIndependentVerification -and
    (
        $RestoreExitCode -ne 0 -or
        $BuildExitCode -ne 0 -or
        $TestExitCode -ne 0
    )
) {
    $RunStatus = "FAILED"
}

$ResultsContent = @"
# Codex Refactoring Results

## Execution

- Date: $($StartTime.ToString("yyyy-MM-dd HH:mm:ss"))
- Completion: $($EndTime.ToString("yyyy-MM-dd HH:mm:ss"))
- Duration: $($Duration.ToString("hh\:mm\:ss"))
- Model: $Model
- Starting Git Commit: $StartingCommit
- Run Status: $RunStatus
- Codex Exit Code: $CodexExitCode
- Thread ID: $($Usage.ThreadId)
- Turn Count: $($Usage.TurnCount)

## Token Usage

- Input Tokens: $($Usage.InputTokens)
- Cached Input Tokens: $($Usage.CachedInputTokens)
- Uncached Input Tokens: $UncachedInputTokens
- Output Tokens: $($Usage.OutputTokens)
- Reasoning Output Tokens: $($Usage.ReasoningOutputTokens)
- Total Tokens: $($Usage.TotalTokens)

## Estimated Cost

- Uncached Input: `$$((Format-Currency $InputCost))
- Cached Input: `$$((Format-Currency $CachedInputCost))
- Output: `$$((Format-Currency $OutputCost))
- Total: `$$((Format-Currency $TotalEstimatedCost))

## Verification

- Restore: $RestoreExitCode
- Build: $BuildStatus
- Test: $TestStatus

## Task File

`REFACTORING-TASK.md` was verified unchanged.

## Execution Directory

`$ExecutionDirectory`

## Final Codex Response

$FinalResponseForResults
"@

Set-Content `
    -LiteralPath $ResultsFile `
    -Value $ResultsContent `
    -Encoding UTF8

# ============================================================
# Final Summary
# ============================================================

Write-Section "Codex Refactoring Exercise Complete"

Write-Host "Run Status       : $RunStatus"
Write-Host "Codex Exit Code  : $CodexExitCode"
Write-Host "Thread ID        : $($Usage.ThreadId)"
Write-Host "Turn Count       : $($Usage.TurnCount)"
Write-Host "Duration         : $($Duration.ToString("hh\:mm\:ss"))"
Write-Host ""
Write-Host "Starting Git Commit:"
Write-Host "  $StartingCommit"
Write-Host ""
Write-Host "Build Status     : $BuildStatus"
Write-Host "Test Status      : $TestStatus"
Write-Host ""
Write-Host "Estimated Cost   : `$$((Format-Currency $TotalEstimatedCost))"
Write-Host ""
Write-Host "Results:"
Write-Host "  $ResultsFile"
Write-Host ""
Write-Host "Execution Logs:"
Write-Host "  $ExecutionDirectory"
Write-Host ""

if ($RunStatus -ne "SUCCESS") {

    Write-Host "[FAILED] Codex refactoring quality gate failed." -ForegroundColor Red
    exit 1
}

Write-Host "[SUCCESS] Codex refactoring and independent verification completed successfully." -ForegroundColor Green
exit 0
