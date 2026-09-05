# frozen_string_literal: true

require 'test_helper'
require_relative '../../contracts/support/integration_generator_contract_helpers'

class GeneratorRobustnessTest < Minitest::Test
  include GeneratorContractHelpers

  test 'generates a structurally different holdout status integration' do
    status_operation = operation_ir.with(
      id: 'lookup-transfer', role: :fetch_status, method: :get,
      path: '/transfers/{transfer_id}',
      parameters: [{ name: 'transfer_id', location: :path, required: true, schema: { type: :string } }],
      request_fields: [], responses: [{ status: 200, example: { 'status' => 'settled' } }], idempotency: {}
    )
    holdout = integration_ir.with(
      provider_key: 'holdout_gateway', provider_class: 'HoldoutGatewayService', env_prefix: 'HOLDOUT_GATEWAY',
      auth_schemes: [{ type: :bearer, location: :header, name: 'Authorization' }],
      operations: [status_operation], status_map: { 'settled' => 'approved' }, money_transformations: [], idempotency: {}
    )

    result = Generator::FileBuilder.new.call(ir: holdout)

    assert_match 'class HoldoutGatewayService', result.service
    assert_match 'def fetch_status', result.service
    assert_match 'URI.encode_uri_component', result.service
    assert_match 'Bearer', result.service
  end

  test 'rejects malicious executable identifiers' do
    malicious = integration_ir.with(provider_class: 'Safe; system("id")')

    error = assert_raises(Generator::GenerationError) do
      Generator::FileBuilder.new.call(ir: malicious)
    end

    assert_equal :invalid_provider_class, error.diagnostic.code
  end

  test 'contains no development provider branches in production generation code' do
    production = Dir.glob(File.expand_path('../../../lib/generator/**/*.rb', __dir__)).map { |path| File.read(path) }.join

    %w[SumUp Adyen PayPal].each { |provider| refute_includes production, provider }
  end

  test 'ignores reserved IR fields without generation behavior' do
    field = operation_ir.request_fields.first.with(
      location: :query, nullable: true, format: :custom,
      transformation: :custom, default: 'unused'
    )
    money = integration_ir.money_transformations.first.merge(from: 'x', to: 'y')
    metadata = integration_ir.source_metadata.merge(openapi: 'unused', mapping_name: 'unused')
    ir = integration_ir.with(
      operations: [operation_ir.with(request_fields: [field])],
      money_transformations: [money], idempotency: nil, configuration: nil,
      source_metadata: metadata
    )

    assert_equal Generator::FileBuilder.new.call(ir: integration_ir), Generator::FileBuilder.new.call(ir:)
  end
end
