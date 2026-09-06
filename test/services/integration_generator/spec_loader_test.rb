# frozen_string_literal: true

require 'test_helper'
require 'yaml'

class IntegrationGeneratorSpecLoaderTest < Minitest::Test
  test 'loads a well-formed YAML document into a plain Hash' do
    document = loader.call(source: "openapi: 3.0.3\ninfo:\n  title: Test\n", source_name: 'spec.yaml')

    assert_equal({ 'openapi' => '3.0.3', 'info' => { 'title' => 'Test' } }, document)
  end

  test 'permits Date and Time scalars used by real provider specs' do
    document = loader.call(source: "openapi: 3.0.3\nretrieved_at: 2026-09-04\n", source_name: 'spec.yaml')

    assert_kind_of Date, document.fetch('retrieved_at')
  end

  test 'rejects malformed YAML with a structured diagnostic' do
    error = assert_raises(IntegrationGenerator::SpecError) do
      loader.call(source: "openapi: [\n", source_name: 'spec.yaml')
    end

    assert_equal :error, error.diagnostic.severity
    assert_equal :invalid_yaml, error.diagnostic.code
  end

  test 'rejects a non-mapping root document' do
    error = assert_raises(IntegrationGenerator::SpecError) do
      loader.call(source: "- one\n- two\n", source_name: 'spec.yaml')
    end

    assert_equal :invalid_yaml, error.diagnostic.code
  end

  test 'rejects YAML aliases' do
    source = <<~YAML
      openapi: 3.0.3
      base: &base
        type: object
      other:
        <<: *base
    YAML

    error = assert_raises(IntegrationGenerator::SpecError) { loader.call(source:, source_name: 'spec.yaml') }

    assert_equal :disallowed_yaml_construct, error.diagnostic.code
  end

  test 'rejects arbitrary Ruby object tags' do
    error = assert_raises(IntegrationGenerator::SpecError) do
      loader.call(source: "openapi: 3.0.3\nvalue: !ruby/object {}\n", source_name: 'spec.yaml')
    end

    assert_equal :disallowed_yaml_construct, error.diagnostic.code
  end

  test 'rejects input above the size limit' do
    oversized = "openapi: '3.0.3'\npadding: '#{'a' * (IntegrationGenerator::SpecLoader::MAX_BYTESIZE + 1)}'\n"

    error = assert_raises(IntegrationGenerator::SpecError) { loader.call(source: oversized, source_name: 'spec.yaml') }

    assert_equal :input_too_large, error.diagnostic.code
  end

  test 'rejects nesting deeper than the configured limit' do
    deeply_nested = { 'leaf' => true }
    (IntegrationGenerator::SpecLoader::MAX_NESTING_DEPTH + 5).times { deeply_nested = { 'nested' => deeply_nested } }
    source = { 'openapi' => '3.0.3', 'deep' => deeply_nested }.to_yaml

    error = assert_raises(IntegrationGenerator::SpecError) { loader.call(source:, source_name: 'spec.yaml') }

    assert_equal :nesting_too_deep, error.diagnostic.code
  end

  private

  def loader
    IntegrationGenerator::SpecLoader.new
  end
end
