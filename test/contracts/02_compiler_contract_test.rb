require "test_helper"
require_relative "support/integration_generator_contract_helpers"

class CompilerContractTest < ActiveSupport::TestCase
  include IntegrationGeneratorContractHelpers

  test "compiler converts OpenAPI and versioned mapping into provider-neutral IR" do
    result = compile(mapping_source: minimal_mapping)

    assert_instance_of IntegrationGenerator::CompileResult, result
    assert_empty result.diagnostics.select { |item| item.severity == :error }
    assert_equal "novapay", result.ir.provider_key
    assert_equal [ :create_request ], result.ir.operations.map(&:role)
    assert_equal "X-API-Key", result.ir.auth_schemes.first.fetch(:name)
    assert_equal "1.0", result.ir.source_metadata.fetch(:mapping_schema_version)
  end

  test "compiler reports missing payment semantics instead of inferring them" do
    result = compile(mapping_source: mapping_without_operation_semantics)

    assert_nil result.ir
    error = result.diagnostics.find { |item| item.code == :ambiguous_operation_role }
    assert_equal :error, error.severity
    assert_match "#/paths", error.source_path
    assert_predicate error.hint, :present?
  end

  test "compiler rejects an unknown mapping version" do
    result = compile(mapping_source: minimal_mapping.sub('schema_version: "1.0"', 'schema_version: "2.0"'))

    assert_nil result.ir
    assert_includes result.diagnostics.map(&:code), :unsupported_mapping_version
  end

  test "compiler rejects remote references with a structured diagnostic" do
    source = minimal_spec.sub(
      "schema:\n                    type: object",
      "schema:\n                    $ref: https://example.test/schemas.yaml#/Payout"
    )
    result = compile(source: source, source_name: "remote-ref.yaml", mapping_source: minimal_mapping)

    assert_nil result.ir
    diagnostic = result.diagnostics.find { |item| item.code == :remote_reference_unsupported }
    assert_equal :error, diagnostic.severity
    assert_predicate diagnostic.source_path, :present?
    assert_predicate diagnostic.hint, :present?
  end

  private

  def compile(source: minimal_spec, source_name: "provider_api.yaml", mapping_source:)
    IntegrationGenerator::Compiler.new.call(
      source: source,
      source_name: source_name,
      mapping_source: mapping_source,
      mapping_source_name: "integration_mapping.yml",
      provider_key: "novapay"
    )
  end
end
