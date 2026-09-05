# Transitional integration-generator contracts

These tests freeze the boundary between two developers before production modules exist. They intentionally fail on missing `Generator::*` constants and become green by milestone; do not skip or weaken them to satisfy CI.

```bash
bundle exec ruby -Itest test/contracts/01_ir_contract_test.rb
bundle exec ruby -Itest test/contracts/02_compiler_contract_test.rb
bundle exec ruby -Itest test/contracts/03_generator_contract_test.rb
bundle exec ruby -Itest test/contracts/04_cli_contract_test.rb
```

Progression:

1. Shared contract freeze makes `01` green.
2. Developer A completes Spec Compiler and makes `02` green.
3. Developer B completes file generation against frozen IR and makes `03` green.
4. Integration makes `04` green.

Run all contracts with `bundle exec ruby -Itest test/contracts`. Internal unit tests belong under `test/services/integration_generator`; the end-to-end test belongs at `test/integration/generation_pipeline_test.rb`.
