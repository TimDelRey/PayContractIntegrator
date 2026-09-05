# frozen_string_literal: true

module IntegrationGenerator
  # Loads the optional integration_mapping.yml. Mapping is never required --
  # it exists only to override what SemanticResolver could not safely infer,
  # or to disambiguate something inference got wrong. A mapping that IS
  # given must be well-formed and on a supported schema_version; unlike a
  # spec's own missing semantics (which degrade gracefully), a broken
  # user-provided override is a hard error -- we cannot trust it partially.
  class MappingLoader
    SUPPORTED_SCHEMA_VERSION = '1.0'

    def call(source:, source_name:)
      return nil if source.nil?

      mapping = SpecLoader.new.call(source: source, source_name: source_name)
      check_schema_version!(mapping, source_name)
      mapping
    end

    private

    def check_schema_version!(mapping, source_name)
      return if mapping['schema_version'] == SUPPORTED_SCHEMA_VERSION

      raise SpecError, Diagnostic.new(
        severity: :error,
        code: :unsupported_mapping_version,
        message: "#{source_name} declares unsupported mapping schema_version #{mapping['schema_version'].inspect}",
        source_path: '#/schema_version',
        hint: "Use mapping schema_version #{SUPPORTED_SCHEMA_VERSION.inspect}"
      )
    end
  end
end
