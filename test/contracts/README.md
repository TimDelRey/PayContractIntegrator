# Transitional routing contracts

These tests intentionally describe the agreed boundary before production modules exist. A missing constant or a failing assertion is expected until its milestone is implemented; do not skip, loosen, or delete a contract merely to make CI green.

Run milestones independently:

```bash
bin/rails test test/contracts/01_value_objects_contract_test.rb
bin/rails test test/contracts/02_eligibility_checker_contract_test.rb
bin/rails test test/contracts/03_engine_contract_test.rb
bin/rails test test/contracts/04_routing_io_contract_test.rb
bin/rails test test/contracts/05_output_contract_test.rb
```

Expected progression:

1. `01` becomes green when `Routing` value objects and errors are implemented.
2. `02` becomes green when all hard constraints and ordered violations are implemented.
3. `03` becomes green when Engine, cascade, fallback, and state transitions are implemented.
4. `04` becomes green when input normalization and deterministic simulation are implemented.
5. `05` becomes green when external projections and analytics are implemented.

The complete contract suite is:

```bash
bin/rails test test/contracts
```

Before changing a public field, enum, reason code, or method signature, update the development plan and get agreement from both module owners. Tests for module-internal implementation details belong outside this directory.
