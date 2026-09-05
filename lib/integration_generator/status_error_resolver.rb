# frozen_string_literal: true

module IntegrationGenerator
  # Builds status_map and error_map across every parsed operation (not just
  # the ones that survived role resolution -- a status enum can live on an
  # operation that got dropped for an unrelated reason). Statuses go through
  # a built-in vocabulary of common payment-status words, since that
  # vocabulary is genuinely shared across providers; errors default to an
  # identity mapping, since provider error codes have no such shared
  # vocabulary to fall back on.
  class StatusErrorResolver
    VOCABULARY = {
      'pending' => 'in_progress', 'processing' => 'in_progress', 'created' => 'in_progress',
      'in_progress' => 'in_progress', 'completed' => 'approved', 'success' => 'approved',
      'succeeded' => 'approved', 'approved' => 'approved', 'done' => 'approved',
      'failed' => 'rejected', 'cancelled' => 'rejected', 'canceled' => 'rejected',
      'rejected' => 'rejected', 'error' => 'rejected'
    }.freeze

    def call(operations:, mapping:, diagnostics:)
      { status_map: status_map(operations, mapping, diagnostics), error_map: error_map(operations, mapping) }
    end

    private

    def status_map(operations, mapping, diagnostics)
      override = (mapping && mapping['status_map']) || {}
      enum_values(operations, 'status').uniq.each_with_object({}) do |value, map|
        mapped = override[value] || VOCABULARY[value.to_s.downcase]
        mapped ? map[value] = mapped : diagnostics << unmapped_diagnostic(value)
      end.freeze
    end

    def error_map(operations, mapping)
      override = (mapping && mapping['error_map']) || {}
      error_code_values(operations).uniq.to_h { |value| [value, override[value] || value] }.freeze
    end

    def enum_values(operations, property_name)
      operations.flat_map do |operation|
        schemas_for(operation).flat_map { |schema| Array(schema.dig('properties', property_name, 'enum')) }
      end
    end

    def error_code_values(operations)
      operations.flat_map do |operation|
        schemas_for(operation).flat_map { |schema| direct_and_nested_error_codes(schema) }
      end
    end

    def direct_and_nested_error_codes(schema)
      Array(schema.dig('properties', 'code', 'enum')) +
        Array(schema.dig('properties', 'error', 'properties', 'code', 'enum'))
    end

    def schemas_for(operation)
      schemas = operation[:responses].map { |response| response[:schema] }.compact
      schemas << operation[:request_body_schema] if operation[:request_body_schema]
      schemas.grep(Hash)
    end

    def unmapped_diagnostic(value)
      Generator::Diagnostic.new(
        severity: :warning,
        code: :unmapped_status_value,
        message: "Status value #{value.inspect} has no known Space Payments mapping",
        source_path: '#/components/schemas',
        hint: 'Add it to integration_mapping.yml status_map'
      )
    end
  end
end
