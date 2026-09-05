# frozen_string_literal: true

require 'test_helper'

class IntegrationGeneratorMappingLoaderTest < Minitest::Test
  test 'returns nil when no mapping source is given' do
    assert_nil loader.call(source: nil, source_name: nil)
  end

  test 'loads a well-formed mapping into a plain Hash' do
    mapping = loader.call(source: "schema_version: \"1.0\"\noperations: []\n", source_name: 'integration_mapping.yml')

    assert_equal({ 'schema_version' => '1.0', 'operations' => [] }, mapping)
  end

  test 'rejects an unsupported mapping schema_version' do
    error = assert_raises(IntegrationGenerator::SpecError) do
      loader.call(source: "schema_version: \"2.0\"\n", source_name: 'integration_mapping.yml')
    end

    assert_equal :error, error.diagnostic.severity
    assert_equal :unsupported_mapping_version, error.diagnostic.code
  end

  test 'reuses SpecLoader safety checks for malformed mapping YAML' do
    error = assert_raises(IntegrationGenerator::SpecError) do
      loader.call(source: "schema_version: [\n", source_name: 'integration_mapping.yml')
    end

    assert_equal :invalid_yaml, error.diagnostic.code
  end

  private

  def loader
    IntegrationGenerator::MappingLoader.new
  end
end
