require 'test_helper'
require_relative 'support/integration_generator_contract_helpers'

class CompilerContractTest < Minitest::Test
  include GeneratorContractHelpers

  test 'compiler infers role and auth from the spec alone, without any mapping' do
    result = compile

    assert_instance_of Generator::CompileResult, result
    refute_nil result.ir
    assert_equal [:create_request], result.ir.operations.map(&:role)
    assert_equal 'X-API-Key', result.ir.auth_schemes.first.fetch(:name)
    assert_includes result.diagnostics.map(&:code), :money_unit_undetermined
  end

  test 'explicit mapping supplies a role the heuristic could not determine' do
    mapping = <<~YAML
      schema_version: "1.0"
      operations:
        - operation_id: getBalance
          role: create_request
    YAML

    result = compile(source: spec_with_unclassifiable_operation, mapping_source: mapping)

    refute_nil result.ir
    assert_equal ['getBalance'], result.ir.operations.map(&:id)
    assert_equal [:create_request], result.ir.operations.map(&:role)
  end

  test 'compiler reports nothing to generate when no operation resolves to a role' do
    result = compile(source: spec_with_unclassifiable_operation)

    assert_nil result.ir
    error = result.diagnostics.find { |item| item.code == :no_operations_resolved }
    refute_nil error
    assert_equal :error, error.severity
    assert_match '#/paths', error.source_path
    refute_nil error.hint
  end

  test 'compiler rejects an unknown mapping version' do
    result = compile(mapping_source: minimal_mapping.sub('schema_version: "1.0"', 'schema_version: "2.0"'))

    assert_nil result.ir
    assert_includes result.diagnostics.map(&:code), :unsupported_mapping_version
  end

  test 'compiler rejects remote references with a structured diagnostic' do
    source = minimal_spec.sub('type: object', '$ref: https://example.test/schemas.yaml#/Payout')
    result = compile(source:, source_name: 'remote-ref.yaml')

    assert_nil result.ir
    diagnostic = result.diagnostics.find { |item| item.code == :remote_reference_unsupported }
    assert_equal :error, diagnostic.severity
    refute_nil diagnostic.source_path
    refute_nil diagnostic.hint
  end

  private

  def compile(source: minimal_spec, source_name: 'provider_api.yaml', mapping_source: nil)
    IntegrationGenerator::Compiler.new.call(
      source:,
      source_name:,
      mapping_source:,
      mapping_source_name: mapping_source && 'integration_mapping.yml',
      provider_key: 'novapay'
    )
  end
end
