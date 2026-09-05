# frozen_string_literal: true

require 'json'
require 'test_helper'
require_relative '../../contracts/support/integration_generator_contract_helpers'

class GuideAndExamplesTest < Minitest::Test
  include GeneratorContractHelpers

  test 'documents configuration auth operations mappings and idempotency' do
    auth = integration_ir.auth_schemes.first.merge(secret: 'literal-secret')
    guide = Generator::FileBuilder.new.call(ir: integration_ir.with(auth_schemes: [auth])).guide

    %w[Configuration Authorization Operations Status Error Webhooks].each do |section|
      assert_match "## #{section}", guide
    end
    assert_match 'X-API-Key', guide
    assert_match 'Idempotency-Key', guide
    refute_match 'literal-secret', guide
  end

  test 'creates parseable synthetic examples and redacts sensitive values' do
    field = operation_ir.request_fields.first.with(
      source_name: 'api_key', target_name: 'api_key', type: :string, transformation: nil
    )
    ir = integration_ir.with(
      operations: [operation_ir.with(request_fields: [field])], money_transformations: []
    )

    examples = JSON.parse(Generator::FileBuilder.new.call(ir:).examples)

    assert_equal '[REDACTED]', examples.dig('operations', 0, 'request', 'api_key')
    assert_kind_of Array, examples.fetch('callbacks')

    response = operation_ir.responses.first.merge(example: { 'phone' => '+79990000000' })
    sanitized_ir = integration_ir.with(operations: [operation_ir.with(responses: [response])])
    sanitized = JSON.parse(Generator::FileBuilder.new.call(ir: sanitized_ir).examples)
    assert_equal '[REDACTED]', sanitized.dig('operations', 0, 'responses', 0, 'example', 'phone')
  end
end
