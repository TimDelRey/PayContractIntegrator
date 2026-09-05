# frozen_string_literal: true

require 'test_helper'
require 'json'
require_relative 'support/integration_generator_contract_helpers'

class GeneratorContractTest < Minitest::Test
  include GeneratorContractHelpers

  test 'generator creates a complete deterministic file set from IR' do
    generator = Generator::FileBuilder.new

    first = generator.call(ir: integration_ir)
    second = generator.call(ir: integration_ir)

    assert_instance_of Generator::Result, first
    assert_equal first, second
    assert_match 'class NovapayService', first.service
    assert_match 'def create_request', first.service
    assert_match '# Novapay Integration', first.guide
    assert_kind_of Hash, JSON.parse(first.examples)

    assert_equal '1.0', first.manifest.fetch('contract_version')
    assert_equal '1.0', first.manifest.fetch('ir_contract_version')
    assert_equal '1.0', first.manifest.fetch('mapping_schema_version')
    assert_equal '1', first.manifest.fetch('adapter_contract_version')
    assert_equal %w[INTEGRATION.md examples.json novapay_service.rb], first.manifest.fetch('checksums').keys.sort
    first.manifest.fetch('checksums').each_value do |checksum|
      assert_match(/^[0-9a-f]{64}$/, checksum)
    end
  end

  test 'generated output references configuration without embedding credential values' do
    result = Generator::FileBuilder.new.call(ir: integration_ir)

    assert_match(/ENV|configuration/, result.service)
    assert_match(/API_KEY|api_key/, result.service)
    refute_match(/test-api-key-value|literal-callback-secret|Bearer\s+[A-Za-z0-9._~-]{16,}/, result.service)
    assert_match 'example.test', result.examples
  end

  test 'generator rejects unsupported IR without returning partial files' do
    unsupported_ir = integration_ir.with(contract_version: '2.0')

    error = assert_raises(Generator::GenerationError) do
      Generator::FileBuilder.new.call(ir: unsupported_ir)
    end

    assert_equal :unsupported_ir_version, error.diagnostic.code
    assert_equal :error, error.diagnostic.severity
  end
end
