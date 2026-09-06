# frozen_string_literal: true

module IntegrationGenerator
  class MoneyResolver
    FIELD_NAMES = %w[amount sum value].freeze
    UNIT_KEYWORDS = {
      /(копе[йе]к|kopeck)/i => 'kopeck',
      /(цент|\bcent\b|minor\s+units?)/i => 'cent',
      /major\s+units?/i => 'major'
    }.freeze
    UNIT_MULTIPLIER = { 'kopeck' => 100, 'cent' => 100, 'major' => 1 }.freeze
    INTERNAL_UNIT = 'rub'

    def call(field_name:, field_schema:, operation_mapping:, diagnostics:, operation_id:)
      return nil unless money_field?(field_name, field_schema)

      override = operation_mapping && operation_mapping['money']
      return from_override(field_name, override) if override && override['field'] == field_name

      from_description(field_name, field_schema, diagnostics, operation_id)
    end

    private

    def money_field?(field_name, field_schema)
      FIELD_NAMES.include?(field_name.to_s.downcase) && %w[integer number].include?(field_schema['type'])
    end

    def from_override(field_name, override)
      {
        transformation: :"#{override['from']}_to_#{override['to']}",
        entry: {
          field: field_name, from: override['from'], to: override['to'],
          multiplier: override['multiplier'], rounding: override['rounding']&.to_sym
        }.freeze
      }
    end

    def from_description(field_name, field_schema, diagnostics, operation_id)
      unit = detect_unit_keyword(field_schema['description'])
      return warn_undetermined(field_name, operation_id, diagnostics) unless unit

      entry = {
        field: field_name, from: INTERNAL_UNIT, to: unit,
        multiplier: UNIT_MULTIPLIER.fetch(unit), rounding: :exact
      }.freeze
      { transformation: :"#{INTERNAL_UNIT}_to_#{unit}", entry: entry }
    end

    def warn_undetermined(field_name, operation_id, diagnostics)
      diagnostics << undetermined_diagnostic(field_name, operation_id)
      nil
    end

    def detect_unit_keyword(description)
      return nil unless description.is_a?(String)

      _, unit = UNIT_KEYWORDS.find { |pattern, _| description.match?(pattern) }
      unit
    end

    def undetermined_diagnostic(field_name, operation_id)
      Generator::Diagnostic.new(
        severity: :warning,
        code: :money_unit_undetermined,
        message: "Could not determine the money unit for '#{field_name}' on #{operation_id}; " \
                 'passed through unconverted',
        source_path: "#/paths (#{operation_id})/requestBody/#{field_name}",
        hint: 'Document the unit in the field description, or add a money override in integration_mapping.yml'
      )
    end
  end
end
