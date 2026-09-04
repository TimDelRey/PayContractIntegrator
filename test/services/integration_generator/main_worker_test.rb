require "test_helper"

class IntegrationGeneratorMainWorkerTest < ActiveSupport::TestCase
  test "runs parsing and then generation" do
    calls = []
    parser = callable { |arguments| calls << [ :parsing, arguments ]; :parsed_input }
    generator = callable { |input| calls << [ :generation, input ]; 0 }

    result = IntegrationGenerator::MainWorker.new(parser: parser, generator: generator).call([ "--spec", "provider.yml" ])

    assert_equal 0, result
    assert_equal [
      [ :parsing, [ "--spec", "provider.yml" ] ],
      [ :generation, :parsed_input ]
    ], calls
  end

  test "does not run generation when parsing fails" do
    parser = callable { |_arguments| raise ArgumentError, "invalid input" }
    generator = callable { |_input| flunk "generation must not run" }
    worker = IntegrationGenerator::MainWorker.new(parser: parser, generator: generator)

    error = assert_raises(ArgumentError) { worker.call([]) }

    assert_equal "invalid input", error.message
  end

  private

  def callable(&block)
    Object.new.tap { |object| object.define_singleton_method(:call, &block) }
  end
end
