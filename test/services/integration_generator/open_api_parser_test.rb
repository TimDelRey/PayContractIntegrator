# frozen_string_literal: true

require 'test_helper'

class IntegrationGeneratorOpenApiParserTest < Minitest::Test
  test 'parses version, servers, security schemes and operations' do
    parsed = parser.call(document: minimal_document, source_name: 'spec.yaml')

    assert_instance_of IntegrationGenerator::ParsedSpec, parsed
    assert_equal '3.0.3', parsed.version
    assert_equal ['https://sandbox.example.test/v1'], parsed.base_urls
    assert_equal ['https://example.test/v1'], parsed.source_metadata.fetch(:alternate_base_urls)

    assert_equal 1, parsed.operations.size
    operation = parsed.operations.first
    assert_equal :post, operation.fetch(:method)
    assert_equal '/payouts', operation.fetch(:path)
    assert_equal 'createPayout', operation.fetch(:id)

    assert_equal 1, parsed.security_schemes.size
    scheme = parsed.security_schemes.first
    assert_equal :api_key, scheme.fetch(:type)
    assert_equal :header, scheme.fetch(:location)
    assert_equal 'X-API-Key', scheme.fetch(:scheme_name)
  end

  test 'rejects unsupported OpenAPI versions' do
    document = minimal_document.merge('openapi' => '2.0')

    error = assert_raises(IntegrationGenerator::SpecError) { parser.call(document: document, source_name: 'spec.yaml') }

    assert_equal :unsupported_openapi_version, error.diagnostic.code
  end

  test 'rejects a document with no servers' do
    document = minimal_document.merge('servers' => [])

    error = assert_raises(IntegrationGenerator::SpecError) { parser.call(document: document, source_name: 'spec.yaml') }

    assert_equal :missing_servers, error.diagnostic.code
  end

  test 'rejects non-HTTPS server URLs' do
    document = minimal_document.merge('servers' => [{ 'url' => 'http://insecure.example.test' }])

    error = assert_raises(IntegrationGenerator::SpecError) { parser.call(document: document, source_name: 'spec.yaml') }

    assert_equal :unsafe_server_scheme, error.diagnostic.code
  end

  private

  def parser
    IntegrationGenerator::OpenApiParser.new
  end

  def minimal_document
    {
      'openapi' => '3.0.3',
      'servers' => [{ 'url' => 'https://sandbox.example.test/v1' }, { 'url' => 'https://example.test/v1' }],
      'paths' => {
        '/payouts' => {
          'post' => {
            'operationId' => 'createPayout',
            'security' => [{ 'ApiKeyAuth' => [] }],
            'responses' => { '201' => { 'description' => 'Created' } }
          }
        }
      },
      'components' => {
        'securitySchemes' => {
          'ApiKeyAuth' => { 'type' => 'apiKey', 'in' => 'header', 'name' => 'X-API-Key' }
        }
      }
    }
  end
end
