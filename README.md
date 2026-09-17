# Codex C# Refactoring Exercise

[![.NET 8](https://img.shields.io/badge/.NET-8-512BD4?logo=dotnet&logoColor=white)](https://dotnet.microsoft.com/)
[![C#](https://img.shields.io/badge/C%23-12-239120?logo=csharp&logoColor=white)](https://learn.microsoft.com/dotnet/csharp/)
[![OpenAI Codex](https://img.shields.io/badge/OpenAI-Codex-412991?logo=openai&logoColor=white)](https://openai.com/codex/)

An AI-assisted C# refactoring exercise that uses **OpenAI Codex**, a configurable multi-agent review process, automated repository reset, and independent .NET verification.

---

## Contents

- [What This Project Does](#what-this-project-does)
- [Repository Structure](#repository-structure)
- [How the Multi-Agent Refactoring Works](#how-the-multi-agent-refactoring-works)
- [The Agents](#the-agents)
- [Prerequisites](#prerequisites)
- [OpenAI API Key Setup](#openai-api-key-setup)
- [Configuration](#configuration)
- [Changing the Refactoring Scenario](#changing-the-refactoring-scenario)
- [Running the Solution](#running-the-solution)
- [What the Runner Does](#what-the-runner-does)
- [Understanding the Output](#understanding-the-output)
- [Results and Logs](#results-and-logs)
- [Verification](#verification)
- [Benchmarks](#benchmarks)
- [Cost and Token Usage](#cost-and-token-usage)
- [Keeping Your Repository Safe](#keeping-your-repository-safe)
- [Troubleshooting](#troubleshooting)
- [Example Run](#example-run)
- [Customising the Exercise](#customising-the-exercise)
- [Credits and Inspiration](#credits-and-inspiration)

---

## What This Project Does

This repository demonstrates a repeatable workflow for using AI agents to refactor an existing C# application.

At a high level:

```text
                 ┌─────────────────────────┐
                 │     REFACTORING-TASK    │
                 │       Task Definition   │
                 └────────────┬────────────┘
                              │
                              ▼
                 ┌─────────────────────────┐
                 │       run.ps1           │
                 │   Orchestration Runner  │
                 └────────────┬────────────┘
                              │
                 ┌────────────┴────────────┐
                 ▼                         ▼
        ┌──────────────────┐      ┌──────────────────┐
        │ Business Analyst │      │ C# Architect     │
        └────────┬─────────┘      └────────┬─────────┘
                 │                         │
                 └────────────┬────────────┘
                              ▼
                    ┌────────────────────┐
                    │   Codex Refactor   │
                    │     + Agents       │
                    └─────────┬──────────┘
                              │
                    ┌─────────┴──────────┐
                    ▼                    ▼
           ┌────────────────┐   ┌─────────────────┐
           │ Test Engineer  │   │ DevOps Reviewer │
           └────────┬───────┘   └────────┬────────┘
                    │                    │
                    └─────────┬──────────┘
                              ▼
                  ┌────────────────────────┐
                  │ Independent .NET Check│
                  │ Restore → Build → Test│
                  └────────────┬───────────┘
                               ▼
                         .results\
```

The current exercise focuses on an `OrderProcessing` solution, but the runner is designed so the **refactoring task can be changed without rewriting the orchestration script**.

---

## Repository Structure

The important repository areas are:

```text
codex-csharp-refactoring\
│
├── .codex\
│   ├── agents\
│   │   ├── business-analyst.toml
│   │   ├── csharp-architect.toml
│   │   ├── test-engineer.toml
│   │   └── devops-reviewer.toml
│   └── config.toml
│
├── .results\
│   ├── codex-run.jsonl
│   ├── codex-final-response.txt
│   ├── results.md
│   └── .codex-run\
│       └── <run timestamp>\
│           ├── prompt.txt
│           ├── stdout.jsonl
│           ├── stderr.log
│           ├── final-response.txt
│           ├── exit-code.txt
│           ├── run-codex.cmd
│           ├── dotnet-restore.log
│           ├── dotnet-build.log
│           └── dotnet-test.log
│
├── src\
│   └── OrderProcessing\
│
├── tests\
│   ├── benchmarks\
│   │   └── OrderProcessing.Benchmarks\
│   └── unit tests\
│       └── OrderProcessing.Tests\
│
├── OrderProcessing.sln
├── REFACTORING-TASK.md
├── README.md
└── run.ps1
```

### Important test-layout rule

BenchmarkDotNet projects belong under:

```text
tests\benchmarks\
```

Unit-test projects belong under:

```text
tests\unit tests\
```

Keeping these separate prevents benchmark code from becoming mixed with ordinary unit and integration tests.

---

## How the Multi-Agent Refactoring Works

The runner uses one main Codex session and gives it a structured task containing specialist roles.

The agents are not four separate scripts that independently modify the repository. They are specialist perspectives that collaborate during the Codex run.

The current workflow is:

1. **Business Analyst** analyses requirements and existing behaviour.
2. **C# Architect** analyses design and refactoring opportunities.
3. **Test Engineer** identifies missing and required verification.
4. **DevOps Reviewer** reviews build, dependency, operational, and delivery concerns.
5. Codex implements the agreed changes.
6. The runner independently executes the .NET verification commands.
7. The runner writes the final results and execution logs into `.results`.

This separation is useful because the AI implementation is not considered successful merely because Codex exits with code `0`. The repository must also pass the independent build and test stage.

---

## The Agents

### 1. Business Analyst

Configuration:

```text
.codex/agents/business-analyst.toml
```

Purpose:

- Understand the existing business rules.
- Identify hidden calculation order and assumptions.
- Find ambiguities and validation gaps.
- Identify edge cases.
- Define acceptance criteria.
- Highlight behaviour that should not accidentally change during refactoring.

Example result from the reference run:

> Documented existing rules, hidden calculation order, ambiguities, validation gaps, edge cases, and acceptance criteria for loyalty and combined search.

---

### 2. C# Architect

Configuration:

```text
.codex/agents/csharp-architect.toml
```

Purpose:

- Review the existing C# architecture.
- Identify coupling and separation-of-concern problems.
- Recommend interfaces and injectable services where appropriate.
- Preserve existing business behaviour while improving maintainability.
- Consider validation, repository boundaries, and object mutability.

The reference run separated order writing from search using:

```text
IOrderWriter
IOrderSearch
```

and added defensive repository copies and stronger null validation.

---

### 3. Test Engineer

Configuration:

```text
.codex/agents/test-engineer.toml
```

Purpose:

- Identify missing test coverage.
- Add unit, integration, regression, and boundary tests where required.
- Verify existing behaviour.
- Cover edge cases introduced by the refactoring.
- Ensure benchmark projects remain separate from normal test projects.

The reference run finished with:

```text
72 passed
0 failed
0 skipped
```

---

### 4. DevOps Reviewer

Configuration:

```text
.codex/agents/devops-reviewer.toml
```

Purpose:

- Review dependencies and build concerns.
- Check for unnecessary infrastructure.
- Consider CI/CD readiness.
- Identify operational and scalability risks.
- Review generated artifacts and repository hygiene.
- Confirm that the solution remains practical to build and run.

The reference run reported no known vulnerable NuGet packages and did not add Docker, database, cloud, or other unjustified infrastructure.

---

# Prerequisites

Before running the exercise, install and configure the following.

## Required

### Windows

The current runner is a PowerShell script and is intended to run on Windows.

You need:

- Windows PowerShell 5.1 or compatible PowerShell environment
- Git
- .NET 8 SDK
- OpenAI API access
- OpenAI Codex CLI

### .NET 8 SDK

Verify:

```powershell
dotnet --version
```

Then verify that the solution can be discovered:

```powershell
dotnet sln OrderProcessing.sln list
```

### Git

Verify:

```powershell
git --version
```

The runner uses Git to restore the exercise portion of the repository to the starting commit before a run.

### OpenAI Codex CLI

Verify:

```powershell
codex --version
```

The reference run used:

```text
codex-cli 0.154.0
```

Your installed version may be different.

### OpenAI API access

The runner requires an OpenAI API key because Codex is executing against the OpenAI API.

---

# OpenAI API Key Setup

OpenAI provides an API key page where keys can be created and managed. The full secret key is shown when it is created, so save it securely. OpenAI also recommends keeping API keys private and protected. See the official [OpenAI API key guidance](https://help.openai.com/en/articles/4936850). 

1. Sign in to the OpenAI API platform.
2. Open the API Keys page:
   https://platform.openai.com/api-keys
3. Create a new secret key.
4. Copy the key immediately and store it securely.
5. Configure the key for the environment in which `codex` runs.

For PowerShell, for the current session:

```powershell
$env:OPENAI_API_KEY = "YOUR_API_KEY"
```

To make it persistent for your Windows user account:

```powershell
[Environment]::SetEnvironmentVariable(
    "OPENAI_API_KEY",
    "YOUR_API_KEY",
    "User"
)
```

Close and reopen PowerShell after setting a persistent environment variable.

Verify that the variable exists without printing the secret:

```powershell
if ($env:OPENAI_API_KEY) {
    Write-Host "OPENAI_API_KEY is configured."
} else {
    Write-Host "OPENAI_API_KEY is not configured."
}
```

**Never commit an API key to Git.**

API billing is separate from a ChatGPT subscription. API usage can be viewed through the OpenAI API platform, and billing may use prepaid credits or other billing arrangements depending on the account. See the [OpenAI billing guidance](https://help.openai.com/en/articles/6640792). 

---

# Configuration

The main configuration is split between:

```text
run.ps1
.codex/config.toml
.codex/agents/*.toml
REFACTORING-TASK.md
```

## `run.ps1`

The PowerShell runner controls:

- repository location
- `.codex` location
- `.results` location
- model
- reset behaviour
- independent verification
- Codex execution
- logging
- final result generation

The current model is configured as:

```powershell
$Model = "gpt-5.6-sol"
```

The runner uses the repository containing `run.ps1` as the working repository.

---

## `.codex/config.toml`

This controls the local Codex configuration.

The reference run reported:

```text
[CONFIG] model_provider = openai
```

The runner also validates that:

```text
CODEX_HOME = <repository>\.codex
```

and that the configuration exists before starting the refactoring.

---

# Changing the Refactoring Scenario

The main scenario is defined in:

```text
REFACTORING-TASK.md
```

This is the file to change when you want to turn the repository into a different refactoring exercise.

The runner intentionally treats the task specification separately from the orchestration script.

## Example scenario changes

You could create a task focused on:

### Legacy architecture

```markdown
## Objective

Refactor the existing OrderProcessing solution to improve separation
of concerns while preserving all externally observable behaviour.

Requirements:

- Do not change business rules.
- Introduce clear service boundaries.
- Reduce direct dependencies.
- Add tests for the existing behaviour.
```

### Performance

```markdown
## Objective

Improve the performance of order searching.

Requirements:

- Preserve search semantics.
- Add benchmarks.
- Compare before/after behaviour.
- Do not introduce a database.
- Keep the public API compatible.
```

### Testing

```markdown
## Objective

Improve the test strategy for the existing application.

Requirements:

- Identify untested business rules.
- Add boundary tests.
- Add regression tests.
- Add integration coverage where appropriate.
- Keep benchmark projects separate.
```

### Security and validation

```markdown
## Objective

Review and improve input validation and error handling.

Requirements:

- Identify unsafe null handling.
- Preserve expected business behaviour.
- Add regression coverage.
- Do not add unrelated infrastructure.
```

## Good task specifications

A strong `REFACTORING-TASK.md` should explain:

1. **Objective** — what should improve.
2. **Scope** — which projects/files may be changed.
3. **Constraints** — what must not change.
4. **Business rules** — behaviour that must be preserved.
5. **Testing requirements** — what must be verified.
6. **Benchmark requirements** — if performance is part of the task.
7. **Repository structure requirements** — especially where tests and benchmarks belong.
8. **Acceptance criteria** — objective conditions for success.

The more explicit the task is, the easier it is to compare different refactoring runs.

---

# Running the Solution

Open PowerShell at the repository root:

```powershell
cd C:\Projects\codex\codex-csharp-refactoring
```

Then run:

```powershell
.\run.ps1
```

The runner uses the directory containing `run.ps1` as the project root.

You should see output similar to:

```text
============================================================
Codex Refactoring Exercise Starting
============================================================
Project Root : C:\Projects\codex\codex-csharp-refactoring
CODEX_HOME   : C:\Projects\codex\codex-csharp-refactoring\.codex
Results      : C:\Projects\codex\codex-csharp-refactoring\.results
Model        : gpt-5.6-sol
```

---

# What the Runner Does

## 1. Cleans previous run output

```text
Cleaning Previous Run Files

[OK] Previous run files cleaned.
```

This keeps the top-level result files representative of the current run.

Detailed historical execution data remains under the timestamped execution directory.

---

## 2. Validates API authentication

```text
============================================================
Validating API Authentication
============================================================

[OK] API key detected.
```

The key itself is never printed.

---

## 3. Validates Codex

```text
============================================================
Validating Codex CLI
============================================================

[OK] Codex CLI: codex-cli 0.154.0
```

---

## 4. Validates local configuration

```text
[OK] CODEX_HOME = C:\Projects\codex\codex-csharp-refactoring\.codex
[OK] config.toml found
[CONFIG] model_provider = openai
[OK] Local Codex configuration passed validation.
```

---

## 5. Validates the task and agents

```text
[OK] Task specification loaded.

[OK] business-analyst.toml
[OK] csharp-architect.toml
[OK] test-engineer.toml
[OK] devops-reviewer.toml

[OK] All predefined agents are available.
```

---

## 6. Resets the exercise repository

The runner protects the orchestration and documentation files while restoring the actual exercise:

```text
[RESET] Restoring tracked exercise files to HEAD...
[RESET] Removing untracked exercise files...
[RESET] Removing generated build/test output...
[VERIFY] Protected runner files remain outside reset scope.

[OK] Exercise repository restored to Git HEAD.
```

Protected files include:

```text
run.ps1
README.md
REFACTORING-TASK.md
.codex
.results
```

This means the runner can be used repeatedly without its own configuration and documentation being destroyed by the exercise reset.

---

## 7. Starts Codex

```text
============================================================
Running Codex Refactoring
============================================================

Working directory: C:\Projects\codex\codex-csharp-refactoring
Model            : gpt-5.6-sol
CODEX_HOME       : C:\Projects\codex\codex-csharp-refactoring\.codex
Prompt transport : stdin

[CODEX] Starting...
[CODEX] Process started.
[CODEX] Thread started: 01a0af14-537d-7d83-89a1-8484e51fc0ce
```

The complete Codex event stream is stored in the results directory.

---

# Understanding the Output

There are three particularly useful top-level result files.

## `results.md`

This is the human-readable summary.

A successful run contains information such as:

```markdown
## Verification

- Restore: 0
- Build: SUCCESS
- Test: SUCCESS
```

It also contains the agent findings, refactoring summary, benchmark results, assumptions, unresolved questions, and remaining risks.

For the reference run:

```text
Final result: 72 passed, 0 failed, 0 skipped.
```

---

## `codex-final-response.txt`

This contains the final response produced by Codex after the refactoring work.

It is useful when you want to inspect the AI's own summary without reading the entire event stream.

The reference response reported:

```text
## C# Architect

Refined the architecture by:

- Keeping OrderProcessor as an orchestration service.
- Separating order writing from search via IOrderWriter and IOrderSearch.
- Adding defensive repository copies.
- Hardening null validation.
- Preserving pricing, promotion, shipping, tax, loyalty, and status calculations.
```

---

## `codex-run.jsonl`

This is the machine-readable Codex execution log.

It contains the event stream generated during the Codex session.

Typical events include:

```text
agent_message
command_execution
collab_tool_call
turn completion
```

A JSONL event log is useful for future automation because another tool can process individual events without parsing a large human-readable transcript.

---

# Results and Logs

All generated results are stored under:

```text
.results\
```

The current reference run produced:

```text
.results\
├── codex-run.jsonl
├── codex-final-response.txt
├── results.md
└── .codex-run\
    └── 20260917-131539\
        ├── prompt.txt
        ├── stdout.jsonl
        ├── stderr.log
        ├── final-response.txt
        ├── exit-code.txt
        ├── run-codex.cmd
        ├── dotnet-restore.log
        ├── dotnet-build.log
        └── dotnet-test.log
```

The timestamped directory is especially useful when comparing multiple executions.

For example:

```text
.results\.codex-run\20260917-131539\
```

means the execution started at approximately:

```text
2026-09-17 13:15:39
```

---

# Verification

Codex completion is followed by independent verification.

The runner executes:

```powershell
dotnet restore
dotnet build --configuration Release --no-restore
dotnet test --configuration Release --no-build --no-restore
```

The reference run produced:

```text
Build succeeded.
    0 Warning(s)
    0 Error(s)
```

and:

```text
Passed!  - Failed:     0,
Passed:    72,
Skipped:     0,
Total:    72
```

This distinction is important:

```text
Codex Exit Code = 0
```

means Codex completed successfully.

It does **not** by itself prove that the resulting C# repository is correct.

The independent .NET verification is the final quality gate.

---

# Benchmarks

The exercise contains a BenchmarkDotNet project at:

```text
tests/benchmarks/OrderProcessing.Benchmarks
```

The reference release results were:

| Orders | No filters | Combined filters |
|---:|---:|---:|
| 100 | 10.179 µs / 37.6 KB | 650.7 ns / 272 B |
| 10,000 | 4.495 ms / 3.78 MB | 202.4 µs / 453 KB |
| 100,000 | 54.548 ms / 37.30 MB | 8.058 ms / 4.49 MB |

Format:

```text
time / allocated memory
```

Calculators were not benchmarked because their operations were considered too trivial to produce useful measurements for this exercise.

### Important

Benchmarks are not a replacement for unit tests.

They answer a different question:

```text
Unit tests       → Does the behaviour remain correct?
Benchmarks       → How does the implementation perform?
```

---

# Cost and Token Usage

The runner records token usage and an estimated cost for the Codex run.

The reference execution reported:

| Metric | Value |
|---|---:|
| Input tokens | 969,907 |
| Cached input tokens | 908,473 |
| Uncached input tokens | 61,434 |
| Output tokens | 3,820 |
| Reasoning tokens | 516 |
| Total tokens | 973,727 |
| Estimated total cost | **$0.6855** |

Cost breakdown:

| Component | Estimated cost |
|---|---:|
| Uncached input | $0.2457 |
| Cached input | $0.3634 |
| Output | $0.0764 |
| **Total** | **$0.6855** |

These figures are **for this specific reference run**. API pricing and model availability can change, so treat the values generated by the runner as the source of truth for each individual execution.

For cost monitoring, OpenAI provides usage and billing information through the API platform.

---

# Keeping Your Repository Safe

The runner deliberately separates the exercise files from the runner itself.

### Exercise scope

```text
OrderProcessing.sln
src\
tests\
```

### Protected runner/documentation scope

```text
run.ps1
README.md
REFACTORING-TASK.md
.codex\
.results\
```

The reset process restores the exercise to the starting Git commit but does not intentionally reset the protected runner files.

This makes it possible to update:

```text
README.md
run.ps1
REFACTORING-TASK.md
```

without losing those changes when the next refactoring run starts.

### API key safety

Do not put:

```text
OPENAI_API_KEY=sk-...
```

into source code, `README.md`, `.codex/config.toml`, or committed logs.

Use an environment variable or another secure secret-management mechanism.

---

# Troubleshooting

## `OPENAI_API_KEY` not detected

Check:

```powershell
if ($env:OPENAI_API_KEY) {
    "API key detected"
} else {
    "API key missing"
}
```

If it is missing:

```powershell
$env:OPENAI_API_KEY = "YOUR_API_KEY"
```

Then run:

```powershell
.\run.ps1
```

---

## Codex command not found

Check:

```powershell
codex --version
```

If PowerShell cannot find it, install/configure the Codex CLI and make sure it is available on `PATH`.

---

## .NET SDK missing

Check:

```powershell
dotnet --version
```

The project targets .NET 8, so install a compatible .NET 8 SDK.

---

## Build fails after a refactoring

Run the verification manually:

```powershell
dotnet restore
dotnet build --configuration Release
dotnet test --configuration Release
```

Then inspect:

```text
.results\.codex-run\<timestamp>\
```

particularly:

```text
dotnet-build.log
dotnet-test.log
stderr.log
stdout.jsonl
```

---

## Tests fail

Start with:

```powershell
dotnet test --configuration Release
```

Then inspect:

```text
.results\results.md
.results\codex-final-response.txt
```

The results summary may identify which agent detected the relevant issue.

---

## Want to understand exactly what Codex did?

Inspect:

```text
.results\codex-run.jsonl
```

and the timestamped:

```text
.results\.codex-run\<timestamp>\stdout.jsonl
```

The JSONL logs contain the detailed event stream.

---

# Example Run

A shortened example of a successful execution:

```text
============================================================
Codex Refactoring Exercise Starting
============================================================
Project Root : C:\Projects\codex\codex-csharp-refactoring
CODEX_HOME   : C:\Projects\codex\codex-csharp-refactoring\.codex
Results      : C:\Projects\codex\codex-csharp-refactoring\.results
Model        : gpt-5.6-sol

[OK] API key detected.
[OK] Codex CLI: codex-cli 0.154.0
[OK] Local Codex configuration passed validation.
[OK] Task specification loaded.
[OK] All predefined agents are available.

[OK] Exercise repository restored to Git HEAD.

============================================================
Running Codex Refactoring
============================================================

[CODEX] Process started.
[CODEX] Thread started: 01a0af14-537d-7d83-89a1-8484e51fc0ce

...

[CODEX] Process completed.
Exit code: 0
Duration : 00:09:55

============================================================
Independent Build and Test Verification
============================================================

Build succeeded.
    0 Warning(s)
    0 Error(s)

Passed! - Failed: 0, Passed: 72, Skipped: 0, Total: 72

============================================================
Codex Refactoring Exercise Complete
============================================================

Run Status       : SUCCESS
Build Status     : SUCCESS
Test Status      : SUCCESS
Estimated Cost   : $0.6855

[SUCCESS] Codex refactoring and independent verification completed successfully.
```

---

# Customising the Exercise

The easiest way to create a new exercise is to keep the runner and agents stable and change the task.

For example:

```text
Same runner
     │
     ├── Architecture exercise
     ├── Performance exercise
     ├── Testing exercise
     ├── Security/validation exercise
     └── Maintainability exercise
```

Change:

```text
REFACTORING-TASK.md
```

Keep:

```text
run.ps1
.codex/config.toml
.codex/agents/
```

This makes it possible to compare how Codex performs against different engineering objectives while keeping the orchestration process consistent.

## Suggested task structure

```markdown
# Refactoring Task

## Objective

Describe the problem.

## Scope

Describe what may be changed.

## Requirements

1. Requirement one.
2. Requirement two.
3. Requirement three.

## Constraints

- Preserve existing business behaviour.
- Do not modify unrelated infrastructure.
- Keep benchmark projects under tests/benchmarks.
- Keep unit tests under tests/unit tests.

## Acceptance Criteria

- The solution builds successfully.
- All existing tests pass.
- New required tests pass.
- No warnings are introduced.
- Required benchmark projects exist and execute.
```

---

# Reference Run Findings

The reference execution resolved the following areas:

- Missing independent calculator tests.
- Missing loyalty and search coverage.
- Mutable repository-state exposure.
- Null collection/line handling.
- Persistence/search interface segregation.
- Missing benchmark project referenced by the solution.

The refactoring introduced injectable services for:

```text
serialization
validation
customer retrieval
pricing
promotions
shipping
tax
loyalty
persistence
search
```

Search supports combined inclusive filters and case-insensitive customer/status matching.

The final verification was:

```text
72 passed
0 failed
0 skipped
```

The agents also identified remaining risks including sustained concurrency/load testing and extreme decimal-overflow scenarios.

---

# Current Known Risks

The reference results identify several areas that may be worth addressing in a future exercise:

- Search is linear.
- Search allocates defensive copies.
- Search holds a lock during scanning.
- Persistence is volatile and scoped to one repository instance.
- Extreme monetary values can overflow.
- There is no checked-in CI workflow.
- The .NET SDK is not pinned.
- `.codex` and `.results` generated artifacts require repository hygiene.

These are useful candidates for future refactoring scenarios rather than reasons to change the current exercise automatically.

---

## Quick Start

If everything is already installed and configured:

```powershell
cd C:\Projects\codex\codex-csharp-refactoring

$env:OPENAI_API_KEY = "YOUR_API_KEY"

.\run.ps1
```

Then open:

```text
.results\results.md
```

For the detailed Codex execution:

```text
.results\codex-run.jsonl
```

For the final AI summary:

```text
.results\codex-final-response.txt
```

For timestamped execution logs:

```text
.results\.codex-run\
```

**The simplest way to think about this repository:**

> Define the engineering problem → let specialist agents analyse it → let Codex implement it → independently build and test the result → inspect the evidence in `.results`.
