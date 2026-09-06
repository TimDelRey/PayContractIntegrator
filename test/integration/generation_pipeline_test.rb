require 'test_helper'
require 'json'
require 'tmpdir'
require_relative '../contracts/support/integration_generator_contract_helpers'

class GenerationPipelineTest < Minitest::Test
  include GeneratorContractHelpers

  test 'runs the real spec, IR adapter, and generator stages end to end through Pipeline' do
    Dir.mktmpdir do |directory|
      spec = File.join(directory, 'provider_api.yaml')
      mapping = File.join(directory, 'integration_mapping.yml')
      output = File.join(directory, 'output')
      File.write(spec, minimal_spec)
      File.write(mapping, minimal_mapping)

      status, paths = Generator::Pipeline.new.call(spec:, mapping:, provider: 'novapay', lang: 'ruby', output:)

      assert_equal :ok, status
      assert_equal [
        File.join(output, 'novapay_service.rb'),
        File.join(output, 'INTEGRATION.md'),
        File.join(output, 'fixtures.json')
      ], paths

      assert_ruby_compiles(File.read(paths[0]))
      assert_kind_of Hash, JSON.parse(File.read(paths[2]))
    end
  end

  test 'generates a complete file set including the webhook callback, inferred without any mapping overrides' do
    Dir.mktmpdir do |directory|
      spec = File.join(directory, 'provider_api.yaml')
      output = File.join(directory, 'output')
      File.write(spec, File.read(webhook_fixture_path))

      status, paths = Generator::Pipeline.new.call(spec:, mapping: minimal_mapping_path(directory), provider: 'novapay', lang: 'ruby', output:)

      assert_equal :ok, status
      service = File.read(paths.find { |path| path.end_with?('_service.rb') })
      assert_match 'def process_callback', service
      assert_match 'verify_webhook_signature!', service
      assert_ruby_compiles(service)
    end
  end

  test 'refuses to publish over an existing output directory without --force' do
    Dir.mktmpdir do |directory|
      spec = File.join(directory, 'provider_api.yaml')
      mapping = File.join(directory, 'integration_mapping.yml')
      output = File.join(directory, 'output')
      File.write(spec, minimal_spec)
      File.write(mapping, minimal_mapping)
      Dir.mkdir(output)

      status, reasons = Generator::Pipeline.new.call(spec:, mapping:, provider: 'novapay', lang: 'ruby', output:)

      assert_equal :publication_failed, status
      assert_match 'output_conflict', reasons.first
    end
  end

  private

  def webhook_fixture_path
    File.expand_path('../fixtures/integration_generator/providers/provider_api.yaml', __dir__)
  end

  def minimal_mapping_path(directory)
    path = File.join(directory, 'integration_mapping.yml')
    File.write(path, 'schema_version: "1.0"')
    path
  end

  def assert_ruby_compiles(source)
    RubyVM::InstructionSequence.compile(source)
  rescue SyntaxError => e
    flunk "generated service does not compile: #{e.message}"
  end
end
