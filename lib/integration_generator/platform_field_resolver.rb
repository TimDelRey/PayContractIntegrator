# frozen_string_literal: true

module IntegrationGenerator
  # Classifies how generated code must read a request-body field's value
  # from the platform's internal `operation` object. Per the platform
  # team's clarification (hackathon Q&A), only operation.id, operation.amount
  # and operation.payout_requisite are guaranteed to exist -- everything
  # else is either a fixed constant (a single-value enum), an id alias, a
  # payout_requisite container, or genuinely unknown. An unknown field is
  # never silently guessed; it stays tagged :unknown so the renderer can
  # leave a TODO instead of inventing a read path.
  class PlatformFieldResolver
    ID_ALIAS_PATTERN = /\A(external_id|merchant_reference|client_reference|reference)\z/i
    REQUISITE_KEYS = %w[phone bank_code bank_name card_number iban account_number].freeze
    TYPE_SELECTOR = 'type'

    def classify(name, field_schema, money:, diagnostics:)
      return requisite_container(name, field_schema, diagnostics) if requisite_shaped?(field_schema)
      return constant(field_schema) if single_value_enum?(field_schema)
      return { kind: :attribute, attribute: Generator::PLATFORM_ATTRIBUTE_AMOUNT }.freeze if money
      return { kind: :attribute, attribute: Generator::PLATFORM_ATTRIBUTE_ID }.freeze if name.to_s.match?(ID_ALIAS_PATTERN)

      { kind: :unknown }.freeze
    end

    private

    def requisite_shaped?(field_schema)
      field_schema['type'] == 'object' && requisite_keys_present(field_schema).any?
    end

    # Only the first alternative of the sibling type-selector enum is
    # resolved (matching the case brief's own reference implementation,
    # which only implements the SBP path) -- picking among several
    # requisite types at runtime is a rendering/branching decision for the
    # Artifact Generator to make, not something to guess here. When more
    # than one alternative exists, that choice is surfaced as a diagnostic
    # rather than made silently.
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
