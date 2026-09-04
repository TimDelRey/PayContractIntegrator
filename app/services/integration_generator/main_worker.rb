module IntegrationGenerator
  class MainWorker
    def initialize(parser:, generator:)
      @parser = parser
      @generator = generator
    end

    def call(arguments)
      parsed_input = parse(arguments)
      generate(parsed_input)
    end

    private

    attr_reader :parser, :generator

    def parse(arguments)
      parser.call(arguments)
    end

    def generate(parsed_input)
      generator.call(parsed_input)
    end
  end
end
