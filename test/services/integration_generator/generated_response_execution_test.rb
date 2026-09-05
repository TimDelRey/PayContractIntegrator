require 'test_helper'
require_relative '../../contracts/support/integration_generator_contract_helpers'

class GeneratedResponseExecutionTest < Minitest::Test
  include GeneratorContractHelpers

  Response = Data.define(:body, :status)
  CreateOperation = Data.define(:amount, :idempotency_key)
  StatusOperation = Data.define(:provider_operation_id)

  class FakeClient
    def initialize(response)
      @response = response
    end

    def post(_url, **) = @response
    def get(_url, **) = @response
  end

  test 'maps provider errors' do
    response = Response.new(body: { 'error' => { 'code' => 'validation_error' } }, status: 422)

    with_service(integration_ir, response) do |service|
      with_env('NOVAPAY_API_KEY', 'synthetic-key') do
        result = service.create_request(CreateOperation.new(amount: 100, idempotency_key: 'test-idempotency'))
        assert result.failed?
        assert_equal [:unprocessable_entity, 'validation_error'], result.errors
      end
    end
  end

  test 'maps fetched provider status' do
    operation = operation_ir.with(
      id: 'fetchPayout', role: :fetch_status, method: :get,
      path: '/payouts/{provider_operation_id}',
      parameters: [{ name: 'provider_operation_id', location: :path }],
      request_fields: [], idempotency: {}
    )
    ir = integration_ir.with(operations: [operation], money_transformations: [], idempotency: {})
    response = Response.new(body: { 'status' => 'completed' }, status: 200)

    with_service(ir, response) do |service|
      with_env('NOVAPAY_API_KEY', 'synthetic-key') do
        result = service.fetch_status(StatusOperation.new(provider_operation_id: 'np_test'))
        assert result.success?
        assert_equal 'approved', result.data
      end
    end
  end

  private

  def with_service(ir, response)
    provider = Module.new
    provider.const_set(:BaseService, Generator::ProviderAdapterContract::V1::BaseService)
    Object.const_set(:Provider, provider)
    Object.class_eval(Generator::FileBuilder.new.call(ir:).service)
    yield Provider::NovapayService.new(client: FakeClient.new(response))
  ensure
    Object.send(:remove_const, :Provider) if Object.const_defined?(:Provider, false)
  end

  def with_env(key, value)
    previous = ENV.fetch(key, nil)
    ENV[key] = value
    yield
  ensure
    previous.nil? ? ENV.delete(key) : ENV[key] = previous
  end
end
