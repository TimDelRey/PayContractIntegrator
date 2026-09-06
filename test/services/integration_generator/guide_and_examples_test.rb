# frozen_string_literal: true

require 'json'
require 'test_helper'
require_relative '../../contracts/support/integration_generator_contract_helpers'

class GuideAndExamplesTest < Minitest::Test
  include GeneratorContractHelpers

  test 'documents configuration auth operations mappings and idempotency' do
    auth = integration_ir.auth_schemes.first.merge(secret: 'literal-secret')
    guide = Generator::FileBuilder.new.call(ir: integration_ir.with(auth_schemes: [auth])).guide

    %w[Configuration Authorization Operations Status Error Webhooks Unresolved].each do |section|
      assert_match "## #{section}", guide
    end
    assert_match 'X-API-Key', guide
    assert_match 'Idempotency-Key', guide
    refute_match 'literal-secret', guide
  end

  test 'lists a field with no resolved platform read path under "Unresolved fields" instead of silently dropping it' do
    field = operation_ir.request_fields.first.with(
      source_name: 'mystery', target_name: 'mystery', required: false, platform_source: { kind: :unknown }
    )
    ir = integration_ir.with(operations: [operation_ir.with(request_fields: [field])], money_transformations: [])

    guide = Generator::FileBuilder.new.call(ir:).guide

    assert_match(/## Unresolved fields\n\n- `createPayout`: `mystery`/, guide)
  end

  test 'reports "None." under "Unresolved fields" when every field has a resolved platform read path' do
    guide = Generator::FileBuilder.new.call(ir: integration_ir).guide

    assert_match(/## Unresolved fields\n\nNone\./, guide)
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

  test 'skips a webhook callback example instead of documenting a null event when its event_map is empty' do
    callback = operation_ir.with(id: 'payoutWebhook', role: :process_callback, request_fields: [], idempotency: {})
    ir = integration_ir.with(
      operations: [callback],
      money_transformations: [],
      webhooks: [{
        signature: {
          algorithm: :hmac_sha256, encoding: :hex, header: 'X-Signature',
          secret_env: 'NOVAPAY_CALLBACK_SECRET', signed_payload: :raw_body
        },
        event_map: {}
      }]
    )

    examples = JSON.parse(Generator::FileBuilder.new.call(ir:).examples)

    assert_empty examples.fetch('callbacks')
  end
end
