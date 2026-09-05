# frozen_string_literal: true

require 'test_helper'
require_relative '../../contracts/support/integration_generator_contract_helpers'

# Cases not already pinned down by the frozen test/contracts/02_compiler_contract_test.rb.
class IntegrationGeneratorCompilerTest < Minitest::Test
  include GeneratorContractHelpers

  test 'a malformed mapping surfaces SpecLoader diagnostics, not a crash' do
    result = compiler.call(
      source: minimal_spec, source_name: 'provider_api.yaml',
      mapping_source: "schema_version: [\n", mapping_source_name: 'integration_mapping.yml',
      provider_key: 'novapay'
    )

    assert_nil result.ir
    assert_includes result.diagnostics.map(&:code), :invalid_yaml
  end

  test 'a mapping money override removes the money_unit_undetermined warning' do
    mapping = <<~YAML
      schema_version: "1.0"
      operations:
        - operation_id: createPayout
          money:
            field: amount
            from: rub
            to: kopeck
            multiplier: 100
            rounding: exact
    YAML

    result = compiler.call(
      source: minimal_spec, source_name: 'provider_api.yaml',
      mapping_source: mapping, mapping_source_name: 'integration_mapping.yml',
      provider_key: 'novapay'
    )

    refute_nil result.ir
    refute_includes result.diagnostics.map(&:code), :money_unit_undetermined
    assert_equal :rub_to_kopeck, result.ir.operations.first.request_fields.first.transformation
  end

  test 'compile is deterministic for identical input' do
    first = compiler.call(source: minimal_spec, source_name: 'provider_api.yaml', provider_key: 'novapay')
    second = compiler.call(source: minimal_spec, source_name: 'provider_api.yaml', provider_key: 'novapay')

    assert_equal first.ir, second.ir
  end

  private

  def compiler
    IntegrationGenerator::Compiler.new
  end
end
