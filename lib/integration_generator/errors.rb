# frozen_string_literal: true

module IntegrationGenerator
  class SpecError < StandardError
    attr_reader :diagnostic

    def initialize(diagnostic)
      @diagnostic = diagnostic
      super(diagnostic.message)
    end
  end
end
