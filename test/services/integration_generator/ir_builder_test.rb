# frozen_string_literal: true

require 'test_helper'

class IntegrationGeneratorIrBuilderTest < Minitest::Test
  test 'assembles a fully-formed, deeply frozen IntegrationIR' do
    parsed = IntegrationGenerator::ParsedSpec.new(
      version: '3.0.3',
      base_urls: ['https://sandbox.example.test/v1'].freeze,
      security_schemes: [].freeze,
      operations: [].freeze,
      source_metadata: {}.freeze
    )
    operation = Generator::OperationIR.new(
      id: 'createPayout', role: :create_request, method: :post, path: '/payouts',
      parameters: [].freeze, request_fields: [].freeze,
      responses: [{ status: '201', schema: nil, example: nil }.freeze].freeze,
      idempotency: { location: :header, name: 'Idempotency-Key' }.freeze
    )
    resolved = {
      operations: [operation].freeze,
      webhooks: [].freeze,
      auth_schemes: [{ type: :api_key, location: :header, name: 'X-API-Key' }.freeze].freeze,
      status_map: { 'pending' => 'in_progress' }.freeze,
      error_map: { 'validation_error' => 'validation_error' }.freeze,
      money_transformations: [{ field: 'amount', from: 'rub', to: 'kopeck', multiplier: 100, rounding: :exact }.freeze].freeze
    }

    ir = builder.call(parsed: parsed, resolved: resolved, mapping: nil, provider_key: 'novapay', source_name: 'provider_api.yaml')

    assert_predicate ir, :frozen?
    assert_equal 'novapay', ir.provider_key
    assert_equal 'NovapayService', ir.provider_class
    assert_equal 'NOVAPAY', ir.env_prefix
    assert_equal({ operation_id: 'createPayout', location: :header, name: 'Idempotency-Key' }, ir.idempotency)
    assert_equal %w[api_key base_url], ir.configuration
    assert_nil ir.source_metadata.fetch(:mapping_name)
    assert_raises(FrozenError) { ir.source_metadata[:name] = 'other.yaml' }
  end

  test 'omits api_key from configuration when no operation needs auth' do
    parsed = IntegrationGenerator::ParsedSpec.new(
      version: '3.0.3', base_urls: ['https://sandbox.example.test/v1'].freeze,
      security_schemes: [].freeze, operations: [].freeze, source_metadata: {}.freeze
    )
    resolved = {
      operations: [].freeze, webhooks: [].freeze, auth_schemes: [].freeze,
      status_map: {}.freeze, error_map: {}.freeze, money_transformations: [].freeze
    }

    ir = builder.call(parsed: parsed, resolved: resolved, mapping: nil, provider_key: 'novapay', source_name: 'provider_api.yaml')

    assert_equal %w[base_url], ir.configuration
    assert_empty ir.idempotency
  end

  test 'records mapping metadata when a mapping was used' do
    parsed = IntegrationGenerator::ParsedSpec.new(
      version: '3.0.3', base_urls: ['https://sandbox.example.test/v1'].freeze,
      security_schemes: [].freeze, operations: [].freeze, source_metadata: {}.freeze
    )
    resolved = {
      operations: [].freeze, webhooks: [].freeze, auth_schemes: [].freeze,
      status_map: {}.freeze, error_map: {}.freeze, money_transformations: [].freeze
    }

    ir = builder.call(
      parsed: parsed, resolved: resolved, mapping: { 'schema_version' => '1.0' },
      provider_key: 'novapay', source_name: 'provider_api.yaml'
    )

    assert_equal 'integration_mapping.yml', ir.source_metadata.fetch(:mapping_name)
    assert_equal '1.0', ir.source_metadata.fetch(:mapping_schema_version)
  end

  private

  def builder
    IntegrationGenerator::IrBuilder.new
  end
end
