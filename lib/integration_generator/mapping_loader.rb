# frozen_string_literal: true

module IntegrationGenerator
  class MappingLoader
    SUPPORTED_SCHEMA_VERSION = '1.0'

    def call(source:, source_name:)
      return nil if source.nil?

      mapping = SpecLoader.new.call(source:, source_name:)
      check_schema_version!(mapping, source_name)
      mapping
    end

    private

    def check_schema_version!(mapping, source_name)
      return if mapping['schema_version'] == SUPPORTED_SCHEMA_VERSION

      raise SpecError, Generator::Diagnostic.new(
        severity: :error,
        code: :unsupported_mapping_version,
        message: "#{source_name} declares unsupported mapping schema_version #{mapping['schema_version'].inspect}",
        source_path: '#/schema_version',
        hint: "Use mapping schema_version #{SUPPORTED_SCHEMA_VERSION.inspect}"
      )
    end
  end
end
