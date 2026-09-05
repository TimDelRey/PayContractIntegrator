module Generator
  class MainWorker
    def initialize(parser:, generator:)
      @parser = parser
      @generator = generator
    end

    def call(arguments)
      input = parser.call(arguments)
      generator.call(input)
    end

    private

    attr_reader :parser, :generator
  end
end
