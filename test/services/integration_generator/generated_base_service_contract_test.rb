# frozen_string_literal: true

require 'test_helper'
require_relative '../../contracts/support/integration_generator_contract_helpers'

class GeneratedBaseServiceContractTest < Minitest::Test
  include GeneratorContractHelpers

  FakeResponse = Data.define(:body)
  Operation = Data.define(:amount, :idempotency_key)

  class FakeClient
    attr_reader :request

    def post(url, json:, headers:)
      @request = { url:, json:, headers: }
      FakeResponse.new(body: { 'status' => 'pending' })
    end
  end

  test 'executes a generated child service against a fake client' do
    install_fake_host
    Object.class_eval(Generator::FileBuilder.new.call(ir: integration_ir).service)
    client = FakeClient.new
    service = Provider::NovapayService.new(client:)

    with_env('NOVAPAY_API_KEY', 'synthetic-key') do
      service.create_request(Operation.new(amount: 100, idempotency_key: 'test-idempotency'))
    end

    assert_operator Provider::NovapayService, :<, Provider::BaseService
    assert_equal 10_000, client.request.dig(:json, 'amount')
    assert_equal 'test-idempotency', client.request.dig(:headers, 'Idempotency-Key')
    assert_equal 'https://sandbox.example.test/v1/payouts', client.request.fetch(:url)
  ensure
    Object.send(:remove_const, :Provider) if Object.const_defined?(:Provider, false)
  end

  private

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
