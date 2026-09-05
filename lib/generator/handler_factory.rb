module Generator
  class HandlerFactory
    REGISTRY = {
      service: Handlers::RubyServiceHandler,
      guide: Handlers::GuideHandler,
      examples: Handlers::ExamplesHandler
    }.freeze
    private_constant :REGISTRY

    def build(file_type:)
      handler_class = REGISTRY[file_type]
      return handler_class.new if handler_class

      raise GenerationError, Diagnostic.new(
        severity: :error, code: :unsupported_file_type,
        message: "No registered handler for #{file_type.inspect}",
        source_path: nil, hint: 'Use a file type from the handler registry'
      )
    end
  end
end
