# Advanced Codex Multi-Agent Refactoring Exercise

## Objective

Refactor the `OrderProcessing` C# solution using the predefined Codex agents:

- `business-analyst`
- `csharp-architect`
- `test-engineer`
- `devops-reviewer`

This is intentionally a realistic legacy-style application. The existing `OrderProcessor` mixes input handling, validation, customer lookup, pricing, promotions, shipping, tax, status management and JSON serialization.

The goal is to improve the architecture **and add new functionality**, while preserving existing observable behaviour unless a documented requirement explicitly changes it.

# 1. Business Analyst

Review the existing solution and document:

- Existing business rules.
- Hidden business rules inside `OrderProcessor`.
- Ambiguous behaviour.
- Missing validation.
- Missing acceptance criteria.
- Edge cases.
- Risks created by mixing business rules and infrastructure.
- Areas where a future change could accidentally alter existing pricing.

Do not invent business rules for existing behaviour.

For the new functionality below, create explicit acceptance criteria before implementation.

# 2. New Functionality: Loyalty Points

Add a loyalty-points feature.

## Rules

### Standard customers

Earn **1 point for every R10 of the final merchandise value after discounts**, rounded down.

### Gold customers

Earn **2 points for every R10 of the final merchandise value after discounts**, rounded down.

### Tax-exempt customers

Loyalty points are calculated using the same merchandise-value rule. Tax exemption does not change the points multiplier.

### Shipping

Shipping must NOT contribute to loyalty points.

### Example

A Gold customer has:

- Merchandise subtotal: R1,000
- Discount: R50
- Merchandise value after discount: R950

Points:

`floor(950 / 10) * 2 = 190 points`

Add the calculated value to the processed order as:

```text
LoyaltyPoints
```

# 3. New Functionality: Order Search

Introduce an order-search capability.

Create an abstraction that allows orders to be searched by:

- Customer ID
- Order status
- Minimum total
- Maximum total
- Created date range

The search API should support combining filters.

For example:

```text
CustomerId = C001
Status = Approved
MinimumTotal = 500
```

should return only orders matching all supplied criteria.

The current implementation does not persist orders.

Introduce a simple in-memory order repository for the exercise.

Do not introduce a database, Entity Framework, Docker or cloud infrastructure.

# 4. C# Architect

Refactor the application so responsibilities are separated.

At minimum, consider separating:

- JSON serialization/deserialization
- Input validation
- Customer retrieval
- Pricing
- Promotion calculation
- Shipping calculation
- Tax calculation
- Loyalty-point calculation
- Order persistence
- Order search

`OrderProcessor` should become an orchestration/application service rather than containing every business rule.

Requirements:

- Use strongly typed models.
- Apply SOLID principles where useful.
- Use dependency injection through constructors.
- Introduce interfaces only where they provide real value.
- Avoid unnecessary abstraction.
- Make business calculations independently unit-testable.
- Make order search independently testable.
- Improve exception handling.
- Avoid static global state.
- Keep the code readable.
- Do not change existing pricing rules unintentionally.

# 5. Test Engineer

Expand the automated tests substantially.

Use Arrange / Act / Assert.

Tests must cover existing behaviour:

## Validation

- Null input.
- Empty input.
- Invalid JSON.
- Missing order ID.
- Missing customer ID.
- Unknown customer.
- No order lines.
- Missing SKU.
- Zero quantity.
- Negative quantity.
- Negative price.

## Pricing

- Basic order.
- Multiple lines.
- Decimal prices.
- Gold customer discount.
- Gold customer below discount threshold.
- Bulk promotion below quantity 10.
- Bulk promotion at quantity 10.
- Bulk promotion above quantity 10.
- Order discount below R2,000.
- Order discount at R2,000.
- Order discount above R2,000.
- Discount cannot exceed merchandise subtotal.

## Shipping

- South African order below free-shipping threshold.
- South African order at free-shipping threshold.
- South African order above free-shipping threshold.
- International order.

## Tax

- Normal customer.
- Tax-exempt customer.
- Decimal rounding.

## Status

- Order below manual-review threshold.
- Order at manual-review threshold.
- Order above manual-review threshold.

## Loyalty

- Standard customer points.
- Gold customer points.
- Decimal merchandise values.
- Points based on merchandise after discount.
- Shipping excluded from points.
- Tax excluded from points.
- Tax exemption does not alter points.

## Search

Test every individual filter:

- Customer ID.
- Status.
- Minimum total.
- Maximum total.
- Created-from.
- Created-to.

Also test:

- No filters.
- Multiple filters.
- No matching orders.
- Multiple matching orders.

Tests must be deterministic.

# 6. DevOps Reviewer

Review the resulting solution for:

- Build reliability.
- Test reliability.
- Dependency risks.
- Configuration.
- Logging and error handling.
- CI/CD readiness.
- Repository maintainability.
- Security concerns.
- Operational concerns.

Do not add infrastructure that is not justified by the exercise.

# 7. Lead / Orchestrator

The lead agent must:

1. Inspect the complete repository.
2. Use the Business Analyst.
3. Use the Test Engineer.
4. Capture existing behaviour in tests.
5. Use the C# Architect.
6. Implement the refactoring.
7. Implement loyalty points.
8. Implement order persistence/search.
9. Use the DevOps Reviewer.
10. Consolidate duplicate findings.
11. Run `dotnet restore`.
12. Run `dotnet build`.
13. Run `dotnet test`.
14. Fix failures.
15. Run the tests again.
16. Perform a final review.

Do not claim success unless commands were actually executed.

# Acceptance Criteria

The exercise is complete only when:

- `OrderProcessor` is primarily an orchestration service.
- Existing pricing behaviour remains covered by tests.
- Pricing, promotion, shipping and tax logic are independently testable.
- Loyalty points are implemented and independently testable.
- Order search is implemented and independently testable.
- Orders can be stored in an in-memory repository.
- Search filters can be combined.
- Strongly typed models are used.
- Dependencies are injectable.
- `dotnet restore` succeeds.
- `dotnet build` succeeds.
- `dotnet test` succeeds.
- Tests cover the required scenarios.
- The final report explains each specialist agent's contribution.
- The final report lists assumptions.
- The final report lists unresolved questions.
- The final report identifies remaining technical risks.

# Important Constraints

- Do not modify `REFACTORING-TASK.md`.
- Do not modify files outside the working repository.
- Do not modify `original-repository`.
- Do not add Docker.
- Do not add Kubernetes.
- Do not add a database.
- Do not add cloud infrastructure.
- Do not introduce unnecessary packages.
- Do not replace the project with a completely unrelated implementation.
- Preserve existing observable behaviour unless the new requirements explicitly change it.

The exercise should demonstrate genuine multi-agent collaboration rather than a single-agent rewrite.
