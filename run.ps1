#Requires -Version 5.1

$ErrorActionPreference = "Stop"

# ============================================================
# Codex Multi-Agent C# Refactoring Runner
# ============================================================

$ProjectRoot = $PSScriptRoot
$CodexHome = Join-Path $ProjectRoot ".codex"
$AgentsDirectory = Join-Path $CodexHome "agents"
$Repository = $ProjectRoot
$TaskFile = Join-Path $ProjectRoot "REFACTORING-TASK.md"

# ============================================================
# All generated result/output files are stored under .results
# ============================================================
$ResultsDirectory = Join-Path $ProjectRoot ".results"
$RunRoot = Join-Path $ResultsDirectory ".codex-run"

$JsonLogFile = Join-Path $ResultsDirectory "codex-run.jsonl"
$FinalResponseFile = Join-Path $ResultsDirectory "codex-final-response.txt"
$ResultsFile = Join-Path $ResultsDirectory "results.md"

# Ensure the results directory exists before any output is written.
if (-not (Test-Path -LiteralPath $ResultsDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $ResultsDirectory -Force | Out-Null
}

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
        $ResultsFile,
        (Join-Path $ResultsDirectory ".codex-run.pid")
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

    Write-Host "[RESET] Checking for processes using repository..." -ForegroundColor Gray

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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryPath
    )

    Write-Host ""
    Write-Host "Resetting Working Repository to Git HEAD" -ForegroundColor Cyan

    $Repository = [IO.Path]::GetFullPath($RepositoryPath).TrimEnd('\')

    # ------------------------------------------------------------
    # Validate repository location
    # ------------------------------------------------------------

    if (-not (Test-Path -LiteralPath $Repository -PathType Container)) {
        throw "Repository directory does not exist: $Repository"
    }

    $gitDirectory = Join-Path $Repository ".git"

    if (-not (Test-Path -LiteralPath $gitDirectory -PathType Container)) {
        throw "The repository does not contain a .git directory: $Repository"
    }

    # ------------------------------------------------------------
    # Validate expected repository structure
    # ------------------------------------------------------------

    $solutionPath = Join-Path $Repository "OrderProcessing.sln"
    $srcPath      = Join-Path $Repository "src"
    $testPath     = Join-Path $Repository "tests"

    if (-not (Test-Path -LiteralPath $solutionPath -PathType Leaf)) {
        throw "Expected solution file was not found: $solutionPath"
    }

    if (-not (Test-Path -LiteralPath $srcPath -PathType Container)) {
        throw "Expected src directory was not found: $srcPath"
    }

    if (-not (Test-Path -LiteralPath $testPath -PathType Container)) {
        throw "Expected tests directory was not found: $testPath"
    }

    Write-Host "[OK] Git repository validated." -ForegroundColor Green

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue

    if (-not $gitCommand) {
        throw "Git executable was not found on PATH."
    }

    Push-Location $Repository

    try {
        $gitRoot = (& git rev-parse --show-toplevel 2>&1).Trim()

        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitRoot)) {
            throw "The directory is not recognised as a Git repository: $Repository"
        }

        $gitRootFull = [IO.Path]::GetFullPath($gitRoot).TrimEnd('\')

        if ($gitRootFull -ne $Repository) {
            throw "Git repository root does not match expected repository path.`nExpected: $Repository`nActual:   $gitRootFull"
        }

        # --------------------------------------------------------
        # Capture HEAD before reset
        # --------------------------------------------------------

        $headCommit = (& git rev-parse HEAD 2>&1).Trim()

        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($headCommit)) {
            throw "Unable to determine the current Git HEAD."
        }

        Write-Host "[GIT] HEAD: $headCommit" -ForegroundColor DarkGray

        $branch = (& git branch --show-current 2>&1).Trim()

        if ([string]::IsNullOrWhiteSpace($branch)) {
            Write-Host "[GIT] Repository is in detached HEAD state." -ForegroundColor Yellow
        }
        else {
            Write-Host "[GIT] Branch: $branch" -ForegroundColor DarkGray
        }

        # --------------------------------------------------------
        # Only reset the actual C# exercise files.
        #
        # These files/directories belong to the runner and must
        # NEVER be reverted or removed by this function:
        #   run.ps1
        #   README.md
        #   REFACTORING-TASK.md
        #   .codex\
        #   .results\
        # --------------------------------------------------------

        Write-Host "[RESET] Stopping processes using the repository..." -ForegroundColor DarkGray

        Stop-ProcessesUsingRepository -RepositoryPath $Repository

        # --------------------------------------------------------
        # Reset tracked exercise files only.
        # --------------------------------------------------------

        Write-Host "[RESET] Restoring tracked exercise files to HEAD..." -ForegroundColor DarkGray

        $restoreOutput = & git restore --source=HEAD --staged --worktree -- OrderProcessing.sln src tests 2>&1

        foreach ($line in $restoreOutput) {
            Write-Host $line
        }

        if ($LASTEXITCODE -ne 0) {
            throw "git restore from HEAD for the exercise files failed."
        }

        # --------------------------------------------------------
        # Remove untracked exercise files/directories only.
        #
        # This deliberately does NOT run git clean against the
        # repository root, so runner files cannot be deleted.
        # --------------------------------------------------------

        Write-Host "[RESET] Removing untracked exercise files..." -ForegroundColor DarkGray

        $cleanOutput = & git clean -fd -- src tests OrderProcessing.sln 2>&1

        foreach ($line in $cleanOutput) {
            Write-Host $line
        }

        if ($LASTEXITCODE -ne 0) {
            throw "git clean for the exercise files failed."
        }

        # --------------------------------------------------------
        # Remove generated build/test output from the exercise.
        # --------------------------------------------------------

        Write-Host "[RESET] Removing generated build/test output..." -ForegroundColor DarkGray

        Get-ChildItem `
            -LiteralPath $srcPath `
            -Directory `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -in @(
                    "bin",
                    "obj",
                    "BenchmarkDotNet.Artifacts"
                )
            } |
            Sort-Object FullName -Descending |
            ForEach-Object {
                try {
                    Remove-Item `
                        -LiteralPath $_.FullName `
                        -Recurse `
                        -Force `
                        -ErrorAction Stop
                }
                catch {
                    Write-Host "[WARN] Could not remove: $($_.FullName)" -ForegroundColor Yellow
                }
            }

        Get-ChildItem `
            -LiteralPath $testPath `
            -Directory `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -in @(
                    "bin",
                    "obj",
                    "BenchmarkDotNet.Artifacts"
                )
            } |
            Sort-Object FullName -Descending |
            ForEach-Object {
                try {
                    Remove-Item `
                        -LiteralPath $_.FullName `
                        -Recurse `
                        -Force `
                        -ErrorAction Stop
                }
                catch {
                    Write-Host "[WARN] Could not remove: $($_.FullName)" -ForegroundColor Yellow
                }
            }

        # --------------------------------------------------------
        # Verify protected runner files still exist.
        # --------------------------------------------------------

        $ProtectedFiles = @(
            (Join-Path $Repository "run.ps1"),
            (Join-Path $Repository "README.md"),
            (Join-Path $Repository "REFACTORING-TASK.md")
        )

        foreach ($ProtectedFile in $ProtectedFiles) {
            if (-not (Test-Path -LiteralPath $ProtectedFile -PathType Leaf)) {
                throw "Protected runner file is missing after reset: $ProtectedFile"
            }
        }

        if (-not (Test-Path -LiteralPath (Join-Path $Repository ".codex") -PathType Container)) {
            throw "Protected .codex directory is missing after reset."
        }

        if (-not (Test-Path -LiteralPath (Join-Path $Repository ".results") -PathType Container)) {
            New-Item -ItemType Directory -Path (Join-Path $Repository ".results") -Force | Out-Null
        }

        # --------------------------------------------------------
        # Verify HEAD has not changed.
        # --------------------------------------------------------

        $currentHead = (& git rev-parse HEAD 2>&1).Trim()

        if ($currentHead -ne $headCommit) {
            throw "Repository reset verification failed.`nOriginal HEAD : $headCommit`nCurrent HEAD  : $currentHead"
        }

        # --------------------------------------------------------
        # Verify protected files were not modified by the reset.
        # --------------------------------------------------------

        Write-Host "[VERIFY] Protected runner files remain outside reset scope." -ForegroundColor DarkGray

        # --------------------------------------------------------
        # Final repository validation.
        # --------------------------------------------------------

        if (-not (Test-Path -LiteralPath $solutionPath -PathType Leaf)) {
            throw "Repository reset completed but solution file is missing: $solutionPath"
        }

        if (-not (Test-Path -LiteralPath $srcPath -PathType Container)) {
            throw "Repository reset completed but src directory is missing: $srcPath"
        }

        if (-not (Test-Path -LiteralPath $testPath -PathType Container)) {
            throw "Repository reset completed but tests directory is missing: $testPath"
        }

        Write-Host ""
        Write-Host "[OK] Exercise repository restored to Git HEAD." -ForegroundColor Green
        Write-Host "     Commit  : $headCommit" -ForegroundColor DarkGray
        Write-Host "     Solution: $solutionPath" -ForegroundColor DarkGray
        Write-Host "     Source  : $srcPath" -ForegroundColor DarkGray
        Write-Host "     Tests   : $testPath" -ForegroundColor DarkGray
        Write-Host "     Protected: run.ps1, README.md, REFACTORING-TASK.md, .codex, .results" -ForegroundColor DarkGray

        return $headCommit
    }
    finally {
        Pop-Location
    }
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
    $Psi.WorkingDirectory = $Repository
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
Write-Host "Results      : $ResultsDirectory"
Write-Host "Model        : $Model"
Write-Host ""

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    Fail "Project root does not exist."
}

if (-not (Test-Path -LiteralPath $Repository -PathType Container)) {
    Fail "Repository does not exist: $Repository"
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

if (-not (Test-Path -LiteralPath $ResultsDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $ResultsDirectory -Force | Out-Null
}

# ============================================================
# Clean previous result files
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
    $StartingCommit = Reset-RepositoryToCommittedState
}
else {

    Push-Location $Repository

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
$Repository

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

   Test and benchmark placement rules:
   - All BenchmarkDotNet benchmark projects MUST be created under:
     tests\\benchmarks\\
   - All unit test projects and unit test files MUST be created under:
     tests\\unit tests\\
   - Do NOT create benchmark projects in a repository-level `benchmarks` folder.
   - Do NOT create unit tests directly under `tests\\` or in any other test folder.
   - Keep benchmark code separate from unit/integration test code.

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

$Repository

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

Write-Host "Working directory: $Repository"
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
$ProcessStartInfo.WorkingDirectory = $Repository
$ProcessStartInfo.UseShellExecute = $false
$ProcessStartInfo.CreateNoWindow = $true
$ProcessStartInfo.Environment["CODEX_HOME"] = $CodexHome
$ProcessStartInfo.Environment["CODEX_API_KEY"] = $env:CODEX_API_KEY

$CodexProcess = New-Object System.Diagnostics.Process
$CodexProcess.StartInfo = $ProcessStartInfo

$RunnerPidFile = Join-Path $ResultsDirectory ".codex-run.pid"
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

# Copy main JSONL/final response to the .results directory.
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

## Results Directory

`$ResultsDirectory`

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
Write-Host "Results Directory:"
Write-Host "  $ResultsDirectory"
Write-Host "Results File:"
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
