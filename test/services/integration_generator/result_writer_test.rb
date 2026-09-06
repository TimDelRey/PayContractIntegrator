# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require_relative '../../contracts/support/integration_generator_contract_helpers'

class ResultWriterTest < Minitest::Test
  include GeneratorContractHelpers

  test 'publishes all files together' do
    Dir.mktmpdir do |directory|
      output = File.join(directory, 'output')
      paths = writer.call(result:, output:)
      assert_equal 3, paths.size
      assert File.file?(File.join(output, 'novapay_service.rb'))
      assert File.file?(File.join(output, 'INTEGRATION.md'))
      assert File.file?(File.join(output, 'fixtures.json'))
    end
  end

  test 'does not overwrite unless force is explicit' do
    Dir.mktmpdir do |directory|
      output = File.join(directory, 'output')
      writer.call(result:, output:)
      error = assert_raises(Generator::PublicationError) do
        writer.call(result:, output:)
      end
      assert_equal :output_conflict, error.diagnostic.code
      writer.call(result:, output:, force: true)
      assert File.file?(File.join(output, 'novapay_service.rb'))
    end
  end

  test 'restores the old output when atomic replacement fails' do
    Dir.mktmpdir do |directory|
      output = File.join(directory, 'output')
      Dir.mkdir(output)
      File.write(File.join(output, 'old.txt'), 'old')
      calls = 0
      renamer = lambda do |from, to|
        calls += 1
        raise Errno::EIO, 'simulated rename failure' if calls == 2

        File.rename(from, to)
      end
      failing_writer = Generator::ResultWriter.new(rename: renamer)

      error = assert_raises(Generator::PublicationError) do
        failing_writer.call(result:, output:, force: true)
      end

      assert_equal :publication_failed, error.diagnostic.code
      assert_equal 'old', File.read(File.join(output, 'old.txt'))
      refute File.exist?(File.join(output, 'novapay_service.rb'))
    end
  end

  private

  def writer = Generator::ResultWriter.new
  def result = Generator::FileBuilder.new.call(ir: integration_ir)
end
