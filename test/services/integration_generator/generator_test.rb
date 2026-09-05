# frozen_string_literal: true

require 'stringio'
require 'test_helper'
require 'tmpdir'
require_relative '../../contracts/support/integration_generator_contract_helpers'

class GeneratorTest < Minitest::Test
  include GeneratorContractHelpers

  Input = Data.define(:ir, :output, :force)

  test 'generates verifies and publishes the complete set' do
    Dir.mktmpdir do |directory|
      stdout = StringIO.new
      worker = Generator::Runner.new(stdout:, stderr: StringIO.new)
      input = Input.new(ir: integration_ir, output: File.join(directory, 'output'), force: false)

      assert_equal 0, worker.call(input)
      assert_equal 3, stdout.string.lines.size
      assert File.file?(File.join(input.output, 'novapay_service.rb'))
    end
  end

  test 'returns generation failure without publishing partial output' do
    Dir.mktmpdir do |directory|
      stderr = StringIO.new
      worker = Generator::Runner.new(stdout: StringIO.new, stderr:)
      input = Input.new(ir: integration_ir.with(contract_version: '2.0'), output: File.join(directory, 'output'), force: false)

      assert_equal 4, worker.call(input)
      refute Dir.exist?(input.output)
      assert_match 'unsupported_ir_version', stderr.string
    end
  end

  test 'returns publication failure for an existing output' do
    Dir.mktmpdir do |directory|
      output = File.join(directory, 'output')
      Dir.mkdir(output)
      worker = Generator::Runner.new(stdout: StringIO.new, stderr: StringIO.new)

      assert_equal 5, worker.call(Input.new(ir: integration_ir, output:, force: false))
    end
  end
end
