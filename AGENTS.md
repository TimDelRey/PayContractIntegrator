# AGENTS.md

Guidance for coding agents working in this repository.

> **Default rule:** keep the solution simple, explicit, and reliable. This is payment routing code: correctness and traceability take priority over cleverness, abstraction, and architectural complexity.

## Instruction precedence

Before reading or applying this file, look for `AGENTS.local.md` in the repository root.

1. Read `AGENTS.local.md` first when it exists.
2. Treat it as repository-local, developer-specific instructions.
3. If it conflicts with this file, `AGENTS.local.md` wins.
4. Never create, modify, commit, or disclose `AGENTS.local.md` unless the user explicitly asks.
5. If it does not exist, continue with this file without creating it.

Also follow any more specific `AGENTS.md` files found deeper in the directory tree for files within their scope.

## Project context

This project implements a smart payout routing engine inside a Ruby on Rails application.

Rails provides the application runtime, loading conventions, configuration, testing integration, and project structure. However, the routing engine itself is primarily domain logic and should not depend on HTTP controllers, Active Record persistence, background jobs, Redis, or external infrastructure unless the requested behavior actually requires them.

The system processes payout operations and selects the most appropriate payment provider according to configurable routing rules.

For each operation it must:

* determine which providers satisfy all hard constraints;
* rank eligible providers according to active routing strategies and soft goals;
* attempt providers in the resulting order;
* fall back to the next eligible provider after rejection or timeout;
* use the configured self-provider fallback when no external provider remains;
* update provider state after processing an operation;
* preserve an explanation of why providers were selected, skipped, or retried.

The project also produces routing analytics and recommendations based on routing results and historical data.

Use Rails conventions when they improve clarity and integration with the repository, but do not introduce Rails components merely because they are available.

In particular:

* do not introduce database persistence unless state must survive beyond the routing run;
* do not introduce controllers or routes unless an HTTP interface is required;
* do not introduce Active Job, Sidekiq, or Redis unless asynchronous processing is required;
* do not model plain routing concepts as Active Record models unless persistence is actually needed;
* prefer plain Ruby objects for routing rules, strategies, scoring, simulation, and reporting logic.

## Core engineering principles

This is payment-system code. Favor simple, reliable, explicit solutions over clever or overly abstract designs.

Correctness of routing decisions and monetary calculations is more important than architectural sophistication.

* Write the simplest implementation that correctly satisfies the requirement.
* Prefer straightforward code that another developer can understand and verify quickly.
* Make important business decisions explicit in code.
* Avoid hidden behavior, implicit state changes, metaprogramming, and unnecessary indirection in payment-critical logic.
* Do not introduce abstractions, design patterns, infrastructure, or dependencies unless they solve a concrete problem in the current implementation.
* Keep classes and methods small, cohesive, and clearly named.
* Prefer keyword arguments for domain operations.
* Use one class per file and keep file paths aligned with constants.
* Separate domain logic from file I/O, serialization, and framework concerns.
* Keep state changes explicit and easy to trace.
* Prefer deterministic behavior where possible.
* Fail explicitly rather than silently producing a potentially incorrect payment routing decision.
* Preserve enough information to explain how every routing decision was made.
* Optimize for correctness and maintainability before performance; optimize only when there is a demonstrated need.
* Follow existing repository conventions and RuboCop configuration.

When choosing between two implementations that satisfy the same requirement, prefer the one with fewer moving parts and fewer failure modes.

Do not confuse simplicity with putting unrelated responsibilities together. Separate components when they represent distinct domain responsibilities, but avoid abstractions created only for future possibilities.

## Payment-system mindset

Treat this project as payment infrastructure even though provider interactions and outcomes may be simulated.

Routing decisions affect where money operations are sent, so small implementation errors can produce financially incorrect behavior.

When making changes:

* treat monetary values, limits, margins, turnover, and percentages as payment-critical data;
* never use `Float` for monetary calculations;
* pay particular attention to boundary conditions around provider limits;
* do not allow soft routing preferences to bypass hard safety constraints;
* ensure provider state used for subsequent routing decisions reflects previously processed operations;
* make fallback behavior explicit and bounded;
* distinguish provider rejection, timeout, ineligibility, and technical failure;
* avoid accidental duplicate processing or state updates within a routing run;
* preserve the order and reasons of provider evaluation for auditability;
* do not silently recover from inconsistent input or impossible routing state;
* keep simulations isolated from eligibility and routing policy so simulated behavior cannot accidentally change business rules.

Prefer conservative behavior when input or state is ambiguous: surface the problem rather than silently making a financially meaningful assumption.

Do not over-engineer production payment infrastructure that the task does not require. Apply payment-system rigor to the behavior that actually exists in this project.

## Routing architecture

Keep the routing engine independent from input/output formats where practical.

Separate these concerns:

* loading and validating input data;
* provider eligibility;
* routing strategies and scoring;
* provider attempt and fallback orchestration;
* mutable routing state and metrics;
* result serialization;
* analytics and recommendations.

Do not place all routing behavior in one service or a large conditional statement.

New providers should normally be supported through data or configuration rather than provider-specific branches in the routing engine.

New routing rules or strategies should be addable without rewriting unrelated routing logic.

Follow the existing repository structure before introducing new directories, namespaces, or architectural conventions.

## Hard constraints

Hard constraints determine whether a provider may process an operation.

Apply hard constraints before soft goals or strategy scoring.

Examples include:

* provider status;
* minimum and maximum operation amount;
* daily amount limit;
* in-progress count and amount limits;
* supported and excluded banks;
* margin restrictions;
* available requisites;
* request intensity limits.

A provider that violates any hard constraint must not become eligible because of a high score or another soft goal.

Keep individual constraints isolated where practical.

Constraint evaluation should provide machine-readable reasons and enough details to explain why a provider was excluded.

Do not silently discard failed constraints.

## Soft goals and routing strategies

Soft goals rank providers that already satisfy all hard constraints.

Supported routing factors may include:

* target share by operation count;
* target share by payment volume;
* provider priority;
* operation amount;
* provider conversion;
* current load;
* request intensity;
* minimum or maximum daily turnover commitments;
* other configurable business parameters.

When several factors are active simultaneously, combine them through an explicit and understandable policy such as scoring, weighting, ordered priorities, or another formal mechanism.

Do not resolve conflicts between routing goals through incidental code order.

The reason a provider outranks another provider should be inspectable and explainable.

Keep strategy parameters outside the core algorithm when practical so they can be changed without modifying routing engine code.

## Routing decisions and explainability

Every routing decision must be traceable.

For every considered provider preserve:

* provider identifier;
* decision such as `selected` or `skipped`;
* a stable machine-readable reason;
* useful details when they help explain the decision.

Preserve the actual order in which providers were considered and attempted.

Do not generate explanations independently from the routing decision. Explanations should come from the same evaluations that caused the decision.

Prefer stable reason codes over free-form text as the primary representation.

Human-readable details may supplement reason codes.

## Fallback behavior

Provider rejection or timeout must not cause hard constraints to be bypassed.

After a failed attempt:

1. exclude the failed provider from further attempts for that operation;
2. choose the next provider from the remaining eligible candidates;
3. preserve the failed attempt in the routing decision;
4. continue until an operation succeeds or no eligible external provider remains.

When the external provider pool is exhausted, use the configured self-provider fallback according to the task requirements.

Avoid unbounded retry loops.

Keep simulated provider outcomes separate from provider eligibility and ranking logic.

## Routing state

Routing decisions may depend on state changed by earlier operations.

Examples include:

* approved daily amount;
* operation count;
* payment volume;
* in-progress count and amount;
* request intensity counters;
* provider utilization.

Update relevant state after each processed operation according to the domain rules.

Do not accidentally calculate every operation against the original provider snapshot.

Keep state mutation explicit and testable.

Do not introduce a database solely to maintain state during a single routing run unless persistence is actually required.

## Money and numeric calculations

Treat monetary calculations as payment-critical behavior.

* Never use binary floating-point arithmetic for monetary values.
* Preserve the monetary units used by the input data.
* Use integers or `BigDecimal` where appropriate.
* Make percentage calculations explicit.
* Define rounding behavior when rounding is necessary.
* Test boundary values around provider limits.
* Avoid implicit numeric conversions that can lose precision.

Do not assume every monetary or percentage value can safely be converted through `Float`.

## Input and output

Treat provided JSON and CSV files as external input.

* Validate required fields before using them.
* Fail with clear errors for malformed or unsupported input.
* Do not mutate source input files unless explicitly required.
* Keep parsing separate from routing logic.
* Keep serialization separate from routing decisions.
* Preserve required output field names and structures exactly.
* Additional fields must not break the required output contract.

The generated routing decision and report files must remain compatible with the provided validation scripts.

Do not change required output formats merely to make the internal architecture cleaner.

## Historical data and analytics

Historical routing data may be used to derive metrics or calibrate routing behavior.

Keep derived metrics separate from raw historical records.

Analytics should be based on actual routing results and state rather than hard-coded conclusions.

Recommendations should be explainable from measured conditions such as:

* deviation from target traffic share;
* deviation from target volume share;
* conversion performance;
* provider rejection rates;
* provider utilization;
* limit utilization;
* inability to satisfy routing goals.

Do not produce recommendations that cannot be traced to available data.

## Determinism and simulation

Prefer deterministic routing for identical input and configuration.

If provider outcomes are simulated probabilistically:

* isolate randomness behind a dedicated boundary;
* allow tests and reproducible runs to control the random seed or simulator;
* do not mix random outcome generation with eligibility or scoring logic.

A routing decision should be reproducible when given the same state, configuration, and simulated outcomes.

## Errors

Use domain-specific errors for meaningful routing failures where they improve clarity.

Distinguish between:

* invalid input;
* no eligible provider;
* provider rejection;
* provider timeout;
* routing configuration errors;
* unexpected technical failures.

Do not use broad exception handling to silently convert programming errors into routing failures.

Do not rescue `StandardError` unless there is a clear boundary where the error is intentionally logged, transformed, or handled.

Never silently continue when doing so could produce an incorrect payment routing result.

## Rails usage

This repository is a Rails application. Use Rails where it provides useful conventions, but keep the routing domain independent from unnecessary framework concerns.

Prefer plain Ruby objects for:

* routing rules;
* hard constraints;
* soft goals;
* scoring;
* provider selection;
* fallback orchestration;
* simulation;
* analytics;
* report generation.

Use `app/services`, `app/models`, `lib`, or another existing repository convention based on the current codebase. Do not create a new architectural convention if the repository already has one.

Active Record should represent persisted domain data, not merely provide a convenient base class.

Do not add database tables solely to hold temporary state for one routing execution.

Do not introduce controllers, routes, jobs, Redis, or other Rails subsystems unless the requested feature needs them.

Use Rails facilities such as configuration, Zeitwerk autoloading, ActiveSupport, logging, and RSpec integration when they simplify the implementation without unnecessarily coupling core routing logic to infrastructure.

Use Rails time-zone APIs such as `Time.current` when application time is required.

## Tests

Use RSpec for new tests unless the repository already establishes another testing convention.

Focus tests on routing behavior rather than implementation details.

Cover the behavior affected by a change and relevant boundary or failure cases.

Important routing scenarios include:

* provider passes all hard constraints;
* individual hard constraints exclude providers correctly;
* boundary values for amount and limits;
* multiple eligible providers;
* conflicting soft goals;
* target traffic and volume distribution;
* provider priority;
* conversion-based preference;
* load-based preference;
* provider rejection;
* provider timeout;
* fallback to the next provider;
* fallback when no external provider remains;
* state updates between sequential operations;
* deterministic behavior;
* malformed input;
* required output structure;
* analytics derived from routing results.

Prefer focused unit specs for isolated domain rules and integration specs for complete routing scenarios.

Do not make real external payment requests in tests.

Use explicit domain values in specs, especially amounts, provider IDs, banks, limits, percentages, timestamps, and expected reason codes.

Do not add tests unrelated to the requested change solely to increase coverage.

## Configuration

Routing behavior should be configurable where requirements indicate that parameters may change.

Do not hard-code values tied to the provided example dataset when they represent business configuration.

Keep configuration validation explicit.

Fail clearly when required routing configuration is invalid or inconsistent.

Do not introduce a generic configuration framework unless the project actually needs one.

## Dependencies

Prefer Ruby standard library, Rails facilities already present in the application, and existing project dependencies when sufficient.

Before adding a dependency:

* verify that equivalent functionality is not already available;
* ensure the dependency materially simplifies the solution;
* prefer actively maintained open-source dependencies;
* avoid dependencies that hide important routing behavior.

Do not add PostgreSQL-specific logic, Redis, Sidekiq, external services, or additional infrastructure unless the task requires them.

Do not add framework components solely for architectural appearance.

The majority of project code must remain Ruby, and prohibited technologies must not be introduced.

## Secrets and sensitive data

Even when provider interactions are simulated, treat payment-related and personal data carefully.

* Never commit secrets, API keys, access tokens, passwords, or provider credentials.
* Do not log or expose sensitive payment or personal data unnecessarily.
* Keep local environment files ignored by Git.
* Use environment variables or existing repository configuration mechanisms for secrets when secrets are actually required.
* Do not add real production payment credentials to examples, fixtures, tests, documentation, or agent instructions.
* Never contact real payment providers unless the user explicitly requests and authorizes it.

## Change workflow

1. Read `AGENTS.local.md` first when present, then the applicable agent instructions.
2. Inspect nearby code, configuration, input examples, validation scripts, and tests before designing a change.
3. Understand whether the requested behavior concerns a hard constraint, soft goal, orchestration rule, state update, simulation, or reporting.
4. Prefer the simplest reliable solution consistent with existing repository conventions.
5. Make the smallest coherent change that satisfies the requirement.
6. Add or update focused tests for the changed behavior.
7. Run focused specs, then the broader relevant suite.
8. Run RuboCop and repository-provided validation scripts relevant to the change.
9. When routing output changes, verify generated files against the required schemas and validators.
10. Review the diff for unrelated changes, hard-coded dataset assumptions, unexplained routing decisions, accidental nondeterminism, unsafe monetary calculations, and unnecessary complexity.

Do not modify unrelated user changes.

Do not commit, push, install infrastructure, contact real payment providers, or perform destructive operations unless the user explicitly requests it.
