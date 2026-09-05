# frozen_string_literal: true

require 'openssl'
require 'test_helper'
require_relative '../../contracts/support/integration_generator_contract_helpers'

class GeneratedWebhookExecutionTest < Minitest::Test
  include GeneratorContractHelpers

  test 'accepts valid raw body signature and rejects invalid signature before payload mapping' do
    install_fake_host
    Object.class_eval(Generator::FileBuilder.new.call(ir: callback_ir).service)
    raw_body = '{"event":"payout.completed"}'

    with_env('NOVAPAY_CALLBACK_SECRET', 'synthetic-secret') do
      signature = OpenSSL::HMAC.hexdigest('SHA256', 'synthetic-secret', raw_body)
      service = Provider::NovapayService.new
      result = service.process_callback(
        raw_body:, headers: { 'X-Signature' => signature }, payload: { 'event' => 'payout.completed' }
      )
      assert result.success?
      assert_equal 'approved', result.data
      assert_raises(SecurityError) do
        service.process_callback(
          raw_body:, headers: { 'X-Signature' => 'invalid' }, payload: { 'event' => 'payout.completed' }
        )
      end
    end
  ensure
    Object.send(:remove_const, :Provider) if Object.const_defined?(:Provider, false)
  end

  private

  def callback_ir
    callback = operation_ir.with(id: 'payoutWebhook', role: :process_callback, request_fields: [], idempotency: {})
    integration_ir.with(
      operations: [callback],
      money_transformations: [],
      webhooks: [{
        signature: {
          algorithm: :hmac_sha256, encoding: :hex, header: 'X-Signature',
          secret_env: 'NOVAPAY_CALLBACK_SECRET', signed_payload: :raw_body
        },
        event_map: { 'payout.completed' => 'approved' }
      }]
    )
  end

  def install_fake_host
    provider = Module.new
    provider.const_set(:BaseService, Generator::ProviderAdapterContract::V1::BaseService)
    Object.const_set(:Provider, provider)
  end

  def with_env(key, value)
    previous = ENV.fetch(key, nil)
    ENV[key] = value
    yield
  ensure
    previous.nil? ? ENV.delete(key) : ENV[key] = previous
  end
end
