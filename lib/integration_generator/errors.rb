# frozen_string_literal: true

module IntegrationGenerator
  # Raised by any pipeline stage on a blocking problem. Always carries a
  # structured Diagnostic so callers never have to parse a message string.
  class SpecError < StandardError
    attr_reader :diagnostic

    def initialize(diagnostic)
      @diagnostic = diagnostic
      super(diagnostic.message)
    end
  end
end
