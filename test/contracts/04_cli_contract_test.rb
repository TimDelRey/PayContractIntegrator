require "test_helper"
require "stringio"
require_relative "support/integration_generator_contract_helpers"

class CliContractTest < ActiveSupport::TestCase
  include IntegrationGeneratorContractHelpers

  test "CLI exposes one successful generation flow and resulting paths" do
    stdout = StringIO.new
    stderr = StringIO.new
    pipeline = Object.new
    pipeline.define_singleton_method(:call) { |**| [ :ok, %w[output/novapay_service.rb output/INTEGRATION.md output/fixtures.json] ] }
    cli = IntegrationGenerator::CLI.new(stdout: stdout, stderr: stderr, pipeline: pipeline)

    status = cli.call(%w[--spec provider_api.yaml --provider novapay --lang ruby --output output])

    assert_equal 0, status
    assert_empty stderr.string
    assert_match "output/novapay_service.rb", stdout.string
    assert_match "output/INTEGRATION.md", stdout.string
    assert_match "output/fixtures.json", stdout.string
  end

  test "CLI surfaces unsupported constructs and fallback information" do
    stdout = StringIO.new
    stderr = StringIO.new
    pipeline = Object.new
    pipeline.define_singleton_method(:call) do |**|
      [ :unsupported, [ "remote_reference_unsupported: no network fallback was used" ] ]
    end
    cli = IntegrationGenerator::CLI.new(stdout: stdout, stderr: stderr, pipeline: pipeline)

    status = cli.call(%w[--spec provider_api.yaml --provider novapay --lang ruby])

    assert_equal 3, status
    assert_match "remote_reference_unsupported", stderr.string
    assert_match "fallback", stderr.string
  end
end
