require "test_helper"
require_relative "support/integration_generator_contract_helpers"

class CompilerContractTest < ActiveSupport::TestCase
  include IntegrationGeneratorContractHelpers

  test "compiler converts OpenAPI input into provider-neutral IR" do
    result = IntegrationGenerator::Compiler.new.call(
      source: minimal_spec,
      source_name: "provider_api.yaml",
      provider_key: "novapay"
    )

    assert_instance_of IntegrationGenerator::CompileResult, result
    assert_empty result.diagnostics.select { |item| item.severity == :error }
    assert_equal "novapay", result.ir.provider_key
    assert_equal [ :create_request ], result.ir.operations.map(&:role)
    assert_equal "X-API-Key", result.ir.auth_schemes.first.fetch(:name)
  end

  test "compiler reports ambiguity instead of guessing payment semantics" do
    ambiguous = minimal_spec.gsub("            x-integration-role: create_request\n", "")

    result = IntegrationGenerator::Compiler.new.call(
      source: ambiguous,
      source_name: "ambiguous.yaml",
      provider_key: "novapay"
    )

    assert_nil result.ir
    error = result.diagnostics.find { |item| item.code == :ambiguous_operation_role }
    assert_equal :error, error.severity
    assert_match "#/paths", error.source_path
  end

  test "compiler rejects remote references with a structured diagnostic" do
    source = minimal_spec.sub(
      "schema:\n                    type: object",
      "schema:\n                    $ref: https://example.test/schemas.yaml#/Payout"
    )

    result = IntegrationGenerator::Compiler.new.call(
      source: source,
      source_name: "remote-ref.yaml",
      provider_key: "novapay"
    )

    assert_nil result.ir
    assert_includes result.diagnostics.map(&:code), :remote_reference_unsupported
  end
end
