module Generator
  class GenerationError < StandardError
    attr_reader :diagnostic

    def initialize(diagnostic)
      @diagnostic = diagnostic
      super(diagnostic.message)
    end
  end
end
