require 'test_helper'
require 'stringio'
require_relative 'support/integration_generator_contract_helpers'

class CliContractTest < Minitest::Test
  include GeneratorContractHelpers

  test 'CLI exposes a successful flat-layout generation flow' do
    stdout, stderr, calls, cli = build_cli(
      result: [:ok, %w[output/novapay_service.rb output/INTEGRATION.md output/examples.json]]
    )

    status = cli.call(base_arguments + %w[--output output])

    assert_equal 0, status
    assert_empty stderr.string
    assert_equal 1, calls.size
    assert_equal 'integration_mapping.yml', calls.fetch(0).fetch(:mapping)
    assert_match 'output/novapay_service.rb', stdout.string
    assert_match 'output/INTEGRATION.md', stdout.string
    assert_match 'output/examples.json', stdout.string
  end

  test 'CLI requires the versioned mapping before invoking the pipeline' do
    _stdout, stderr, calls, cli = build_cli(result: [:ok, []])

    status = cli.call(%w[--spec provider_api.yaml --provider novapay --lang ruby])

    assert_equal 2, status
    assert_empty calls
    assert_match(/--mapping/, stderr.string)
  end

  test 'CLI surfaces structured unsupported diagnostics and fallback information' do
    diagnostic = Generator::Diagnostic.new(
      severity: :error,
      code: :remote_reference_unsupported,
      message: 'Remote references are unsupported; no network fallback was used',
      source_path: '#/paths/~1payouts/post/requestBody/$ref',
      hint: 'Replace the remote reference with a local component'
    )
    _stdout, stderr, _calls, cli = build_cli(result: [:unsupported, [diagnostic]])

    status = cli.call(base_arguments)

    assert_equal 3, status
    assert_match 'remote_reference_unsupported', stderr.string
    assert_match diagnostic.source_path, stderr.string
    assert_match diagnostic.hint, stderr.string
    assert_match 'fallback', stderr.string
  end

  test 'CLI maps generation and publication failures to stable exit codes' do
    _stdout, _stderr, _calls, generation_cli = build_cli(result: [:generation_failed, ['verification failed']])
    _stdout, _stderr, _calls, publication_cli = build_cli(result: [:publication_failed, ['output conflict']])

    assert_equal 4, generation_cli.call(base_arguments)
    assert_equal 5, publication_cli.call(base_arguments + %w[--force])
  end

  test 'CLI help succeeds without invoking the pipeline' do
    stdout, stderr, calls, cli = build_cli(result: [:ok, []])

    assert_equal 0, cli.call(['--help'])
    assert_empty stderr.string
    assert_empty calls
    assert_match '--mapping', stdout.string
    assert_match '--force', stdout.string
  end

  private

  def base_arguments
    %w[
      --spec provider_api.yaml
      --mapping integration_mapping.yml
      --provider novapay
      --lang ruby
    ]
  end

  def build_cli(result:)
    stdout = StringIO.new
    stderr = StringIO.new
    calls = []
    pipeline = Object.new
    pipeline.define_singleton_method(:call) do |**arguments|
      calls << arguments
      result
    end
    cli = Generator::CLI.new(stdout: stdout, stderr: stderr, pipeline: pipeline)

    [stdout, stderr, calls, cli]
  end
end
