# frozen_string_literal: true

require 'test_helper'
require_relative '../../contracts/support/integration_generator_contract_helpers'

class FileVerifierTest < Minitest::Test
  include GeneratorContractHelpers

  test 'accepts a complete generated file set' do
    assert_silent { Generator::FileVerifier.new.call(result:) }
  end

  test 'rejects modified content' do
    modified = result.with(examples: "{}\n")
    error = assert_raises(Generator::GenerationError) do
      Generator::FileVerifier.new.call(result: modified)
    end
    assert_equal :checksum_mismatch, error.diagnostic.code
  end

  test 'rejects unsafe paths before publication' do
    manifest = result.manifest.merge('checksums' => result.manifest.fetch('checksums').merge('../escape' => 'invalid'))
    error = assert_raises(Generator::GenerationError) do
      Generator::FileVerifier.new.call(result: result.with(manifest:))
    end
    assert_equal :unsafe_file_path, error.diagnostic.code
  end

  test 'rejects valid JSON with an invalid examples schema' do
    examples = "{}\n"
    checksum = Digest::SHA256.hexdigest(examples)
    checksums = result.manifest.fetch('checksums').dup
    checksums['fixtures.json'] = checksum
    modified = result.with(examples:, manifest: result.manifest.merge('checksums' => checksums))

    error = assert_raises(Generator::GenerationError) do
      Generator::FileVerifier.new.call(result: modified)
    end
    assert_equal :invalid_examples_contract, error.diagnostic.code
  end

  test 'rejects unsafe service install path' do
    error = assert_raises(Generator::GenerationError) do
      Generator::FileVerifier.new.call(result: result.with(service_path: '../service.rb'))
    end
    assert_equal :unsafe_file_path, error.diagnostic.code
  end

  private

  def result = Generator::FileBuilder.new.call(ir: integration_ir)
end
