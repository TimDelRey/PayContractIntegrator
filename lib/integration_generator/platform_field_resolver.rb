# frozen_string_literal: true

module IntegrationGenerator
  class PlatformFieldResolver
    ID_ALIAS_PATTERN = /\A(external_id|reference|\w+_reference)\z/i
    ACCOUNT_ALIAS_PATTERN = /\A(merchant_?(code|id|account)|account_?id|store_?id)\z/i
    REQUISITE_KEYS = %w[phone bank_code bank_name card_number iban account_number].freeze
    MONEY_CONTAINER_VALUE_KEYS = %w[value amount].freeze
    MONEY_CONTAINER_CURRENCY_KEY = 'currency'
    TYPE_SELECTOR = 'type'

    def classify(name, field_schema, money:, diagnostics:)
      return requisite_container(name, field_schema, diagnostics) if requisite_shaped?(field_schema)
      return constant(field_schema) if single_value_enum?(field_schema)
      return { kind: :attribute, attribute: Generator::PLATFORM_ATTRIBUTE_AMOUNT }.freeze if money
      return { kind: :attribute, attribute: Generator::PLATFORM_ATTRIBUTE_ID }.freeze if name.to_s.match?(ID_ALIAS_PATTERN)
      return { kind: :configuration, name: env_variable_name(name) }.freeze if name.to_s.match?(ACCOUNT_ALIAS_PATTERN)

      { kind: :unknown }.freeze
    end

    def money_container_shaped?(field_schema)
      !money_container_value_key(field_schema).nil?
    end

    def money_container_value_schema(field_schema)
      key = money_container_value_key(field_schema)
      field_schema.dig('properties', key)
    end

    private

    def env_variable_name(name)
      name.to_s.gsub(/([a-z0-9])([A-Z])/, '\1_\2').upcase
    end

    def money_container_value_key(field_schema)
      return nil unless field_schema['type'] == 'object'

      properties = field_schema['properties'] || {}
      return nil unless properties.key?(MONEY_CONTAINER_CURRENCY_KEY)

      MONEY_CONTAINER_VALUE_KEYS.find { |key| %w[integer number].include?(properties.dig(key, 'type')) }
    end

    def requisite_shaped?(field_schema)
      field_schema['type'] == 'object' && requisite_keys_present(field_schema).any?
    end

    def requisite_container(name, field_schema, diagnostics)
      properties = field_schema['properties'] || {}
      types = Array(properties.dig(TYPE_SELECTOR, 'enum'))
      known = requisite_keys_present(field_schema)
      diagnostics << ambiguous_type_diagnostic(name, types) if types.size > 1

      {
        kind: :requisite_container,
        requisite_type: types.first,
        known_keys: known,
        unknown_keys: (properties.keys - known - [TYPE_SELECTOR]).freeze
      }.freeze
    end

    def ambiguous_type_diagnostic(name, types)
      Generator::Diagnostic.new(
        severity: :warning,
        code: :ambiguous_requisite_type,
        message: "Field '#{name}' has #{types.size} possible requisite types (#{types.join(', ')}); " \
                 "only '#{types.first}' is resolved for now",
        source_path: "#/components/schemas (#{name})",
        hint: 'Add a requisite_type override in integration_mapping.yml if another type must be supported too'
      )
    end

    def requisite_keys_present(field_schema)
      (Array(field_schema['properties']&.keys) & REQUISITE_KEYS).freeze
    end

    def single_value_enum?(field_schema)
      Array(field_schema['enum']).size == 1
    end

    def constant(field_schema)
      { kind: :constant, value: field_schema.fetch('enum').first }.freeze
    end
  end
end
