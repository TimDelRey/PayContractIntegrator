# frozen_string_literal: true

require 'test_helper'

class GeneratorMainWorkerTest < Minitest::Test
  test 'runs parsing and then generation' do
    calls = []
    parser = callable do |arguments|
      calls << [:parsing, arguments]
      :parsed_input
    end
    generator = callable do |input|
      calls << [:generation, input]
      0
    end
    worker = Generator::MainWorker.new(parser:, generator:)

    result = worker.call(['--spec', 'provider.yml'])

    assert_equal 0, result
    assert_equal [
      [:parsing, ['--spec', 'provider.yml']],
      %i[generation parsed_input]
    ], calls
  end

  test 'does not run generation when parsing fails' do
    parser = callable { |_arguments| raise ArgumentError, 'invalid input' }
    generator = callable { |_input| flunk 'generation must not run' }
    worker = Generator::MainWorker.new(parser:, generator:)

    error = assert_raises(ArgumentError) { worker.call([]) }

    assert_equal 'invalid input', error.message
  end

  private

  def callable(&)
    Object.new.tap { |object| object.define_singleton_method(:call, &) }
  end
end
