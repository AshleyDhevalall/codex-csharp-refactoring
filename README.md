# Complex C# Codex Multi-Agent Refactoring Exercise

A deliberately imperfect .NET 8 C# order-processing application for the Codex multi-agent refactoring workflow.

## Scenario

The legacy `OrderProcessor` handles JSON parsing, validation, customer lookup, promotions, shipping, VAT, totals and status in one class. It also has incomplete automated coverage.

The refactoring task requires the agents to:

1. Preserve and test existing behaviour.
2. Split responsibilities using a maintainable architecture.
3. Add loyalty-point calculation.
4. Add an in-memory order repository.
5. Add combined order search filters.
6. Expand the unit-test suite substantially.
7. Run restore, build and test.

## Commands

```powershell
dotnet restore
dotnet build --configuration Release --no-restore
dotnet test --configuration Release --no-build --no-restore
```

Run the performance benchmarks separately from the functional test suite:

```powershell
dotnet run --project "tests/benchmarks/OrderProcessing.Benchmarks/OrderProcessing.Benchmarks.csproj" --configuration Release
```

## Intended use

The parent Codex `run.ps1` should reset `sample-repository` from `original-repository`, read `REFACTORING-TASK.md` as read-only, and execute the multi-agent exercise.
