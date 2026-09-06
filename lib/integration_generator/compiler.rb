# frozen_string_literal: true

module IntegrationGenerator
  class Compiler
    def call(source:, source_name:, provider_key:, mapping_source: nil, mapping_source_name: nil)
      parsed = parse_structure(source, source_name)
      mapping = MappingLoader.new.call(source: mapping_source, source_name: mapping_source_name)
      resolved = SemanticResolver.new.call(parsed:, mapping:, provider_key:)

      build_result(parsed, resolved, mapping, provider_key, source_name)
    rescue SpecError => e
      Generator::CompileResult.new(ir: nil, diagnostics: [e.diagnostic].freeze)
    end

    private

    def parse_structure(source, source_name)
      document = SpecLoader.new.call(source:, source_name:)
      document = LocalRefResolver.new.call(document:, source_name:)
      OpenApiParser.new.call(document:, source_name:)
    end

    def build_result(parsed, resolved, mapping, provider_key, source_name)
      diagnostics = resolved.fetch(:diagnostics).dup

      unless resolved.fetch(:operations).any? { |operation| operation.role == :create_request }
        diagnostics << no_operations_resolved_diagnostic
        return Generator::CompileResult.new(ir: nil, diagnostics: diagnostics.freeze)
      end

      ir = IrBuilder.new.call(
        parsed:, resolved:, mapping:,
        provider_key:, source_name:
      )
      Generator::CompileResult.new(ir:, diagnostics: diagnostics.freeze)
    end

    def no_operations_resolved_diagnostic
      Generator::Diagnostic.new(
        severity: :error,
        code: :no_operations_resolved,
        message: 'No operation could be resolved to a create_request role; nothing to generate',
        source_path: '#/paths',
        hint: 'Add an operation entry with role: create_request in integration_mapping.yml, ' \
              'or document the operation clearly enough for it to be inferred'
      )
    end
  end
end
