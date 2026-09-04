# frozen_string_literal: true

require 'test_helper'

class SpecParsingPipelineTest < Minitest::Test
  FIXTURE_PATH = File.expand_path(
    '../fixtures/integration_generator/providers/novapay_provider_api.yaml', __dir__
  )

  test 'parses the real NovaPay specification end to end through stages 1-3' do
    source = File.read(FIXTURE_PATH)
    source_name = 'novapay_provider_api.yaml'

    document = IntegrationGenerator::SpecLoader.new.call(source: source, source_name: source_name)
    document = IntegrationGenerator::LocalRefResolver.new.call(document: document, source_name: source_name)
    parsed = IntegrationGenerator::OpenApiParser.new.call(document: document, source_name: source_name)

    assert_equal '3.0.3', parsed.version
    assert_equal 'https://api.sandbox.novapay.example/v1', parsed.base_urls.first
    assert_equal ['https://api.novapay.example/v1'], parsed.source_metadata.fetch(:alternate_base_urls)

    ids = parsed.operations.map { |operation| operation.fetch(:id) }
    assert_equal %w[createPayout getPayoutStatus cancelPayout payoutWebhook getBalance], ids

    assert_equal 1, parsed.security_schemes.size
    scheme = parsed.security_schemes.first
    assert_equal :api_key, scheme.fetch(:type)
    assert_equal :header, scheme.fetch(:location)
    assert_equal 'X-API-Key', scheme.fetch(:scheme_name)

    create_payout = parsed.operations.find { |operation| operation.fetch(:id) == 'createPayout' }
    request_schema = create_payout.fetch(:request_body_schema)
    refute request_schema.key?('$ref'), 'requestBody schema should be fully dereferenced'
    assert_equal 'object', request_schema['type']
    assert request_schema.dig('properties', 'amount'), 'amount field should survive $ref resolution'

    webhook = parsed.operations.find { |operation| operation.fetch(:id) == 'payoutWebhook' }
    assert_empty webhook.fetch(:security)
    signature_param = webhook.fetch(:parameters).find { |parameter| parameter['name'] == 'X-NovaPay-Signature' }
    refute_nil signature_param, 'the webhook signature header parameter should be parsed'
  end
end
