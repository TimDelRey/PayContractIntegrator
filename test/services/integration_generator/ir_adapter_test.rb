require 'test_helper'
require_relative '../../contracts/support/integration_generator_contract_helpers'

class IrAdapterTest < Minitest::Test
  include GeneratorContractHelpers

  WEBHOOK_FIXTURE_PATH = File.expand_path(
    '../../fixtures/integration_generator/providers/provider_api.yaml', __dir__
  )

  test 'adapts a real Spec Compiler IR into the Generator IR contract' do
    compiled = compile_block_one
    result = Generator::IrAdapter.new.call(ir: compiled.ir)

    assert_instance_of Generator::CompileResult, result
    assert_empty result.diagnostics
    ir = result.ir

    assert_instance_of Generator::IntegrationIR, ir
    assert_equal compiled.ir.schema_version, ir.contract_version
    assert_equal compiled.ir.provider_key, ir.provider_key
    assert_equal [], ir.webhooks

    operation = ir.operations.first
    assert_instance_of Generator::OperationIR, operation
    assert_equal :create_request, operation.role
    assert_instance_of Generator::FieldIR, operation.request_fields.first
    assert_equal :rub_to_kopeck, operation.request_fields.first.transformation

    # The Compiler only detects idempotency from a header parameter, so this fixture's mapping-only override leaves it nil.
    assert_nil compiled.ir.operations.first.idempotency
    assert_equal({}, operation.idempotency)
  end

  test 'refuses to invent webhook signature secrets or event maps' do
    spec = File.read(WEBHOOK_FIXTURE_PATH)
    compiled = IntegrationGenerator::Compiler.new.call(source: spec, source_name: 'provider_api.yaml', provider_key: 'novapay')
    refute_nil compiled.ir
    refute_empty compiled.ir.webhooks

    result = Generator::IrAdapter.new.call(ir: compiled.ir)

    assert_nil result.ir
    assert_equal 1, result.diagnostics.size
    diagnostic = result.diagnostics.first
    assert_instance_of Generator::Diagnostic, diagnostic
    assert_equal :error, diagnostic.severity
    assert_equal :webhook_contract_unsupported, diagnostic.code
    assert_equal '/webhooks/payout', diagnostic.source_path
  end

  private

  def compile_block_one
    IntegrationGenerator::Compiler.new.call(
      source: minimal_spec, source_name: 'provider_api.yaml', provider_key: 'novapay',
      mapping_source: minimal_mapping, mapping_source_name: 'integration_mapping.yml'
    )
  end
end
