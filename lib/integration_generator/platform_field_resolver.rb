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

    def classify(name, field_schema, money:)
      return requisite_container(field_schema) if requisite_shaped?(field_schema)
      return constant(field_schema) if single_value_enum?(field_schema)
      return { kind: :attribute, attribute: 'amount' }.freeze if money
      return { kind: :attribute, attribute: 'id' }.freeze if name.to_s.match?(ID_ALIAS_PATTERN)

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
    # Artifact Generator to make, not something to guess here.
    def requisite_container(field_schema)
      properties = field_schema['properties'] || {}
      known = requisite_keys_present(field_schema)
      {
        kind: :requisite_container,
        requisite_type: properties.dig(TYPE_SELECTOR, 'enum')&.first,
        known_keys: known,
        unknown_keys: (properties.keys - known - [TYPE_SELECTOR]).freeze
      }.freeze
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
