# frozen_string_literal: true

require 'test_helper'
require_relative '../../contracts/support/integration_generator_contract_helpers'

class GeneratedServiceValidationTest < Minitest::Test
  include GeneratorContractHelpers

  test 'rejects ambiguous authentication alternatives' do
    ir = integration_ir.with(auth_schemes: integration_ir.auth_schemes * 2)
    error = assert_raises(Generator::GenerationError) { generate(ir) }
    assert_equal :unsupported_auth_alternatives, error.diagnostic.code
  end

  test 'rejects status operation without explicit mapping' do
    status = operation_ir.with(role: :fetch_status)
    error = assert_raises(Generator::GenerationError) do
      generate(integration_ir.with(operations: [status], status_map: {}))
    end
    assert_equal :missing_status_mapping, error.diagnostic.code
  end

  test 'rejects unsupported operation parameters' do
    query = { name: 'page', location: :query, required: false, schema: { type: :integer } }
    operation = operation_ir.with(parameters: [query])
    error = assert_raises(Generator::GenerationError) do
      generate(integration_ir.with(operations: [operation]))
    end
    assert_equal :unsupported_operation_parameter, error.diagnostic.code
  end

  test 'rejects non-scalar mappings before rendering executable Ruby' do
    malicious = Object.new
    malicious.define_singleton_method(:inspect) { 'system("id")' }
    ir = integration_ir.with(status_map: { malicious => 'approved' })

    error = assert_raises(Generator::GenerationError) { generate(ir) }

    assert_equal :invalid_status_mapping, error.diagnostic.code
  end

  test 'rejects unknown operation role' do
    operation = operation_ir.with(role: :unknown)
    error = assert_raises(Generator::GenerationError) do
      generate(integration_ir.with(operations: [operation]))
    end
    assert_equal :unsupported_operation_role, error.diagnostic.code
  end

  test 'rejects unsupported adapter contract' do
    metadata = integration_ir.source_metadata.merge(adapter_contract_version: '2')
    error = assert_raises(Generator::GenerationError) do
      generate(integration_ir.with(source_metadata: metadata))
    end
    assert_equal :unsupported_adapter_contract, error.diagnostic.code
  end

  test 'rejects input outside the IR contract' do
    error = assert_raises(Generator::GenerationError) { generate(nil) }
    assert_equal :unsupported_ir_version, error.diagnostic.code
  end

  test 'rejects malformed IR collections' do
    error = assert_raises(Generator::GenerationError) do
      generate(integration_ir.with(operations: nil))
    end
    assert_equal :invalid_ir_structure, error.diagnostic.code
  end

  test 'rejects unsupported authentication' do
    ir = integration_ir.with(auth_schemes: [{ type: :oauth2 }])
    error = assert_raises(Generator::GenerationError) { generate(ir) }
    assert_equal :unsupported_auth_scheme, error.diagnostic.code
  end

  test 'rejects unsupported money conversion' do
    money = integration_ir.money_transformations.first.merge(rounding: :half_up)
    error = assert_raises(Generator::GenerationError) do
      generate(integration_ir.with(money_transformations: [money]))
    end
    assert_equal :unsupported_money_rounding, error.diagnostic.code
  end

  test 'rejects unsupported idempotency location' do
    operation = operation_ir.with(idempotency: { location: :query, name: 'request_id' })
    error = assert_raises(Generator::GenerationError) do
      generate(integration_ir.with(operations: [operation]))
    end
    assert_equal :unsupported_idempotency, error.diagnostic.code
  end

  test 'rejects incomplete webhook configuration' do
    operation = operation_ir.with(role: :process_callback, idempotency: {})
    error = assert_raises(Generator::GenerationError) do
      generate(integration_ir.with(operations: [operation], webhooks: []))
    end
    assert_equal :ambiguous_webhook_contract, error.diagnostic.code
  end

  test 'rejects duplicate operation roles' do
    duplicate = operation_ir.with(id: 'anotherCreate')
    error = assert_raises(Generator::GenerationError) do
      generate(integration_ir.with(operations: [operation_ir, duplicate]))
    end
    assert_equal :ambiguous_operation_role, error.diagnostic.code
  end

  test 'rejects duplicate money rules for one field' do
    money = integration_ir.money_transformations.first
    error = assert_raises(Generator::GenerationError) do
      generate(integration_ir.with(money_transformations: [money, money]))
    end
    assert_equal :ambiguous_money_transformation, error.diagnostic.code
  end

  private

  def generate(ir) = Generator::FileBuilder.new.call(ir:)
end
