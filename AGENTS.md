# AGENTS.md

Guidance for coding agents working in this repository.

> **Default rule:** keep solutions simple, explicit, and reliable. This is payment routing code: correctness and traceability take priority over cleverness and architectural complexity.

## Instruction precedence

Before applying this file, look for `AGENTS.local.md` in the repository root.

1. Read `AGENTS.local.md` first when it exists.
2. If it conflicts with this file, `AGENTS.local.md` wins.
3. Never create, modify, commit, or disclose `AGENTS.local.md` unless explicitly requested.
4. Follow more specific `AGENTS.md` files found deeper in the directory tree for files within their scope.

## Project context

This is a Ruby on Rails application implementing payment routing.

Use Rails conventions where useful, but keep core routing logic independent from unnecessary framework and infrastructure concerns.

Do not introduce persistence, controllers, jobs, Redis, Sidekiq, external services, or other infrastructure unless required by the task.

Prefer plain Ruby objects for domain logic that does not require Rails-specific behavior.

## Provider documentation and missing data

When provider behavior, field semantics, limits, statuses, error codes, retry rules, or another integration detail is missing or ambiguous, search official public provider documentation before making an assumption.

* Prefer first-party provider documentation, API references, schemas, changelogs, and status documentation over blogs, aggregators, or examples from third parties.
* Treat unresolved questions and risks found during code, architecture, or development-plan review as explicit research tasks before implementation. Research the affected providers and validate the proposed behavior against current payment-industry practices.
* For industry practices, prefer primary and authoritative sources such as published standards, regulator or payment-network guidance, and provider documentation. For language and framework practices, prefer official Ruby documentation, Rails Guides/API documentation, and the conventions already established in this repository.
* Apply researched practices proportionally to the current task. Do not introduce speculative infrastructure, compliance claims, or complexity that the repository does not require.
* Record the source URL, document version or access date, and the conclusion that affects implementation or tests.
* Capture each material research conclusion in the development plan or decision notes, then reflect it in the relevant contract, configuration, and focused tests so the decision remains traceable.
* Treat repository requirements, supplied case data, samples, and validators as authoritative for this project when they intentionally differ from real provider behavior.
* If official public documentation does not resolve the ambiguity, state the remaining assumption explicitly in the development notes and encode it in configuration or a focused test where appropriate.
* Do not invent undocumented provider behavior or silently copy behavior from a different provider.
* Documentation research is read-only authorization. Never call a live payment API, create provider resources, use credentials, or initiate money movement unless explicitly authorized.

## Engineering principles

* Prefer the simplest implementation that fully satisfies the requirement.
* Write straightforward code that is easy to read, verify, test, and debug.
* Keep business decisions and state changes explicit.
* Keep classes and methods small and cohesive.
* Separate domain logic from I/O, serialization, persistence, and framework concerns.
* Avoid unnecessary abstractions, metaprogramming, hidden behavior, and speculative extensibility.
* Do not introduce dependencies or infrastructure without a concrete need.
* Prefer deterministic behavior where possible.
* Fail clearly rather than silently producing an incorrect result.
* Follow existing repository structure, conventions, and RuboCop configuration.
* Make the smallest coherent change required; do not refactor unrelated code.

When several approaches satisfy the requirement, prefer the one with fewer moving parts and failure modes.

## Payment-system considerations

Treat payment-related code as high-risk even when provider behavior is simulated.

* Prioritize correctness and traceability over convenience.
* Never use `Float` for monetary calculations; use integers or `BigDecimal` as appropriate.
* Preserve monetary precision and make rounding explicit when required.
* Pay particular attention to limits and boundary conditions.
* Keep financially meaningful state changes explicit and testable.
* Do not allow lower-priority business preferences to bypass mandatory constraints.
* Distinguish business rejection, ineligibility, timeout, and technical failure where relevant.
* Keep retries and fallback behavior explicit and bounded.
* Avoid duplicate processing and duplicate state updates.
* Preserve enough information to explain financially meaningful decisions.
* Do not silently recover from inconsistent payment state or ambiguous input.

Do not over-engineer production payment infrastructure that the current task does not require.

## Domain design

Keep business rules separate from infrastructure.

* Prefer domain components that can be tested independently.
* Avoid large classes or conditional structures mixing unrelated rules.
* Keep rule precedence and interactions explicit.
* Do not duplicate the same business rule across layers.
* Keep decision explanations and reason codes tied to the logic that produced them.
* Prefer configuration over hard-coded sample-specific behavior when values represent business settings.
* Make new behavior consistent with existing architecture before introducing new patterns.

## State, I/O, and simulation

Keep mutations and external I/O at clear boundaries.

* Avoid global mutable state and accidental dependencies on execution order.
* Apply state changes consistently when they affect subsequent processing.
* Do not mutate source input unless explicitly required.
* Validate external input before relying on it.
* Preserve required external formats exactly.
* Keep parsing and serialization outside core domain logic.
* Keep simulation and randomness separate from business rules.
* Make randomness controllable in tests when used.

Use repository-provided validators when changing externally consumed output.

## Rails usage

Use Rails where it simplifies the implementation without unnecessarily coupling domain logic to the framework.

* Use Active Record for data that actually requires persistence.
* Do not add database tables for temporary processing state without a persistence requirement.
* Do not add controllers or routes without an HTTP requirement.
* Do not add jobs or queue infrastructure without an asynchronous processing requirement.
* Follow the existing repository structure before introducing new directories or namespaces.
* Use Rails facilities already available in the project before adding dependencies.
* Use Rails time-zone APIs such as `Time.current` when application time is required.

## Errors

Handle expected domain failures explicitly.

Do not broadly rescue errors just to continue execution.

Never convert unexpected programming errors into valid-looking payment results.

Never hide fallback behavior as an ordinary successful path. Surface fallback usage to the caller and ultimately to the user, including why fallback was required, which prior options were exhausted or rejected, and the resulting status. If fallback itself fails or its behavior is ambiguous, propagate that condition explicitly instead of silently recovering.

Use domain-specific errors or result objects when they make behavior clearer.

Do not expose sensitive information in errors or logs.

## Tests

Use RSpec unless the repository establishes another convention.

* Test behavior rather than implementation details.
* Cover the changed behavior, relevant boundaries, and meaningful failure cases.
* Verify state changes when they affect subsequent decisions.
* Prefer focused unit tests for isolated domain behavior and integration tests when component interaction matters.
* Keep domain values explicit in tests.
* Keep tests deterministic.
* Never make real payment-provider calls in tests.
* Do not add unrelated tests solely to increase coverage.

## Dependencies and security

Prefer Ruby standard library, Rails facilities already present, and existing dependencies.

Add a dependency or infrastructure component only when it solves a concrete requirement and materially improves the implementation.

Never commit or expose secrets, credentials, access tokens, private keys, or real payment-provider credentials.

Do not log sensitive payment or personal data unnecessarily.

Never contact real payment providers or initiate real money movement unless explicitly authorized.

## Change workflow

1. Read applicable agent instructions.
2. Read the relevant requirement.
3. Inspect nearby code, tests, configuration, examples, and validators.
4. Identify affected payment invariants, state changes, boundaries, and failure cases.
5. Choose the simplest reliable solution consistent with existing conventions.
6. Make the smallest coherent change.
7. Add or update focused tests.
8. Run relevant specs, RuboCop, and repository validators.
9. Review the diff for unrelated changes, unnecessary complexity, unsafe monetary calculations, hidden state changes, sample-specific assumptions, nondeterminism, and sensitive data.

Do not modify unrelated user changes.

Do not commit, push, install infrastructure, contact real payment providers, or perform destructive operations unless explicitly requested.
