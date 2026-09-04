# AGENTS.md

Guidance for coding agents working in this repository.

> **Default rule:** keep solutions simple, explicit, secure, and deterministic. This repository generates payment-provider integration code, so correctness, traceability, and safe failure take priority over cleverness.

## Instruction precedence

Read `AGENTS.local.md` first when it exists; it wins on conflict. Never create, modify, commit, or disclose it unless explicitly requested. Follow deeper `AGENTS.md` files within their scope.

## Current project context

This Rails repository generates Ruby integrations from public payment-provider API specifications. The current requirement is `thoughts/idea_2.md`. Do not use superseded routing requirements, contracts, tests, or terminology as product requirements.

The pipeline safely parses a provider specification, normalizes it into a provider-neutral intermediate representation (IR), validates supported semantics, and generates a `Provider::BaseService` implementation, `INTEGRATION.md`, `fixtures.json`, and a clear CLI result.

Prefer plain Ruby objects. Do not add persistence, controllers, jobs, queues, or external services unless explicitly required.

## Research and missing information

When supplied data or repository contracts are missing or ambiguous, research before assuming.

- Prefer supplied case files and validators for project-specific behavior.
- Use official public provider API documentation for provider behavior.
- Use the official OpenAPI specification matching the declared document version for API-description semantics.
- Prefer official Ruby documentation, Rails Guides/API docs, primary payment/security standards, regulator or payment-network guidance.
- Treat unresolved review findings as explicit research tasks before implementation.
- Record source URL, version/access date, conclusion, and affected contract/test in development notes.
- If research cannot resolve ambiguity, report an unsupported or ambiguous construct to the caller and user. Never invent provider behavior.
- Research is read-only authorization. Never call live APIs, use credentials, create resources, or move money unless explicitly authorized.

## Generator architecture

Keep stages separate: safe input loading; OpenAPI/version validation and local reference resolution; immutable provider-neutral IR; semantic validation and diagnostics; deterministic template rendering; artifact verification; atomic publication.

Parsing must not render files. Templates must not inspect raw YAML. Generated services must not embed behavior absent from the IR. Use explicit registries for supported auth schemes, operations, transformations, and template versions. Unsupported constructs produce structured diagnostics with source location and severity.

## Security and generated code

Treat specifications as untrusted input.

- Use `Psych.safe_load`; do not deserialize arbitrary Ruby objects or YAML aliases by default.
- Bound input size, nesting, reference traversal, and cycles.
- Do not fetch remote `$ref` URLs by default; explicit future support must prevent SSRF.
- Never interpolate untrusted text directly into executable Ruby. Validate identifiers and render escaped Ruby literals.
- Never generate credentials or secrets; reference environment/configuration.
- Signature verification uses exact documented bytes and constant-time comparison where applicable.
- Preserve documented idempotency requirements.
- Do not expose credentials, signatures, personal payment data, or real customer data in code, logs, docs, errors, or fixtures.
- Generation and verification never contact a provider.

## Contracts and failures

The actual host `Provider::BaseService` contract is authoritative. If unavailable, use an explicit versioned adapter contract and surface that assumption.

Distinguish invalid syntax, unsupported spec version/construct, ambiguous semantics, invalid mapping, rendering failure, artifact verification failure, and publication failure. Do not emit plausible incomplete code when required payment/security semantics are unresolved.

Never hide fallback behavior as success. Surface every fallback/default mapping/template with its reason and source. Authorization, signature, money-unit, status, error, and idempotency gaps must never fall back silently.

## Data, determinism, and output

Never use `Float` for money. Preserve units, conversions, and rounding explicitly in IR, code, docs, and tests. Keep required/optional/null semantics, enums, formats, parameters, responses, statuses, and errors traceable to source or explicit config.

The same input, generator/config/template versions must produce byte-identical artifacts. Validate all artifacts before atomically publishing the complete set. Do not leave mixed old/new output or overwrite existing output unless explicitly requested.

## Tests

Use Minitest unless the repository convention changes.

- Separate parser, IR, validation, renderer, security, CLI, and end-to-end tests.
- Use provider-neutral fixtures and at least two structurally different specs.
- Cover missing/optional fields, response variants, auth alternatives, callbacks/webhooks, units, mappings, local references, cycles, unsupported and malicious input, and atomic rollback.
- Compile generated Ruby with `ruby -c`, run RuboCop, validate JSON, and execute generated contract tests with fake clients.
- Never call providers in tests; use synthetic non-sensitive data and deterministic tests.
- Remove or replace superseded routing tests; they must not remain in default CI.

## Dependencies

Prefer Ruby standard library, existing Rails facilities, and existing dependencies. Add only open-source dependencies with a concrete need after checking maintenance, license, and security. Proprietary technology and neural networks inside the project are prohibited.

## Change workflow

1. Read applicable instructions and `thoughts/idea_2.md`.
2. Inspect the specification, host contract, examples, tests, and validators.
3. Research unresolved provider/OpenAPI/security semantics.
4. Confirm versioned IR and output contracts.
5. Change one pipeline stage coherently and add focused positive/negative tests.
6. Run relevant tests, generated-artifact checks, RuboCop, Brakeman, and dependency audit.
7. Review for provider-specific leakage, unsafe parsing/interpolation, silent fallback, nondeterminism, secrets, and partial output.

Do not modify unrelated user changes. Do not commit, push, install infrastructure, contact providers, or perform destructive operations unless explicitly requested.
