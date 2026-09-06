# frozen_string_literal: true

require 'test_helper'

class FullCompilePipelineTest < Minitest::Test
  FIXTURE_PATH = File.expand_path(
    '../fixtures/integration_generator/providers/novapay_provider_api.yaml', __dir__
  )

  test 'compiles the real NovaPay specification end to end without any mapping' do
    source = File.read(FIXTURE_PATH)

    result = IntegrationGenerator::Compiler.new.call(
      source:, source_name: 'novapay_provider_api.yaml', provider_key: 'novapay'
    )

    refute_nil result.ir
    ir = result.ir

    assert_equal 'NovapayService', ir.provider_class
    assert_equal(
      { 'createPayout' => :create_request, 'getPayoutStatus' => :fetch_status,
        'cancelPayout' => :cancel, 'payoutWebhook' => :process_callback },
      ir.operations.to_h { |operation| [operation.id, operation.role] }
    )
    refute_includes ir.operations.map(&:id), 'getBalance'

    assert_equal 1, ir.webhooks.size
    webhook = ir.webhooks.first
    assert_equal(
      { algorithm: :hmac_sha256, encoding: :hex, signed_payload: :raw_body,
        header: 'X-NovaPay-Signature', secret_env: 'NOVAPAY_CALLBACK_SECRET' },
      webhook.fetch(:signature)
    )
    assert_equal(
      { 'payout.completed' => 'approved', 'payout.failed' => 'rejected',
        'payout.processing' => 'in_progress', 'payout.cancelled' => 'rejected' },
      webhook.fetch(:event_map)
    )

    assert_equal [{ type: :api_key, location: :header, name: 'X-API-Key' }], ir.auth_schemes

    assert_equal(
      { 'pending' => 'in_progress', 'processing' => 'in_progress', 'completed' => 'approved',
        'failed' => 'rejected', 'cancelled' => 'rejected' },
      ir.status_map
    )
    refute_empty ir.error_map

    assert_equal(
      [{ field: 'amount', from: 'rub', to: 'kopeck', multiplier: 100, rounding: :exact }],
      ir.money_transformations
    )

    assert_equal({ operation_id: 'createPayout', location: :header, name: 'Idempotency-Key' }, ir.idempotency)
    assert_equal %w[api_key base_url], ir.configuration

    create_payout = ir.operations.find { |operation| operation.id == 'createPayout' }
    platform_sources = create_payout.request_fields.to_h { |field| [field.source_name, field.platform_source] }
    assert_equal({ kind: :attribute, attribute: 'amount' }, platform_sources.fetch('amount'))
    assert_equal({ kind: :constant, value: 'RUB' }, platform_sources.fetch('currency'))
    assert_equal({ kind: :attribute, attribute: 'id' }, platform_sources.fetch('external_id'))
    assert_equal :requisite_container, platform_sources.fetch('recipient').fetch(:kind)
    assert_equal 'sbp', platform_sources.fetch('recipient').fetch(:requisite_type)

    diagnostic = result.diagnostics.find { |item| item.code == :unresolved_operation_role }
    refute_nil diagnostic, 'getBalance should be dropped with a diagnostic, not silently ignored'
    assert_equal :warning, diagnostic.severity
  end
end
