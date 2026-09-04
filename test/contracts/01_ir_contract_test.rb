require "test_helper"
require_relative "support/integration_generator_contract_helpers"

class IrContractTest < ActiveSupport::TestCase
  include IntegrationGeneratorContractHelpers

  test "IR exposes the frozen boundary between compiler and generator" do
    ir = integration_ir

    assert_equal "1.0", ir.schema_version
    assert_equal "novapay", ir.provider_key
    assert_equal :create_request, ir.operations.first.role
    assert_equal :rub_to_kopeck, ir.operations.first.request_fields.first.transformation
    assert_equal "3.1.0", ir.source_metadata.fetch(:openapi)
  end

  test "contract objects have value semantics and reject unknown fields" do
    assert_equal integration_ir, integration_ir
    assert_raises(ArgumentError) do
      IntegrationGenerator::Diagnostic.new(**diagnostic.to_h, unknown: true)
    end
  end

  test "compile result carries either usable IR or error diagnostics" do
    success = IntegrationGenerator::CompileResult.new(ir: integration_ir, diagnostics: [ diagnostic ])
    failure = IntegrationGenerator::CompileResult.new(
      ir: nil,
      diagnostics: [ diagnostic(severity: :error, code: :ambiguous_operation_role) ]
    )

    assert_equal integration_ir, success.ir
    assert_nil failure.ir
    assert_equal :error, failure.diagnostics.first.severity
    assert_equal "#/paths/~1payouts/post", failure.diagnostics.first.source_path
  end
end
