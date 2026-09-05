# frozen_string_literal: true

module IntegrationGenerator
  # Builds FieldIR objects for an operation's parameters and request body,
  # delegating money-unit detection to MoneyResolver. Also spots the
  # idempotency parameter by name pattern.
  class FieldResolver
    IDEMPOTENCY_NAME_PATTERN = /idempotency/i

    def initialize(money_resolver: MoneyResolver.new)
      @money_resolver = money_resolver
    end

    def parameters(raw_parameters)
      raw_parameters.map { |param| build_parameter_field(param) }
    end

    def body_fields(operation:, mapping_entry:, diagnostics:, money_transformations:)
      schema = operation[:request_body_schema]
      return [] unless schema.is_a?(Hash)

      context = {
        required: Array(schema['required']), mapping_entry: mapping_entry, diagnostics: diagnostics,
        operation_id: operation[:id], money_transformations: money_transformations
      }
      overrides = (mapping_entry && mapping_entry['fields']) || {}

      (schema['properties'] || {}).map do |name, field_schema|
        build_body_field(name, field_schema, overrides[name], context)
      end
    end

    def idempotency(parameters)
      param = parameters.find { |field| field.source_name.to_s.match?(IDEMPOTENCY_NAME_PATTERN) }
      return nil unless param

      { location: param.location, name: param.source_name }.freeze
    end

    private

    def build_parameter_field(param)
      schema = param['schema'] || {}
      FieldIR.new(
        source_name: param['name'], target_name: param['name'], location: param['in']&.to_sym,
        required: param['required'] == true, nullable: schema['nullable'] == true,
        type: schema['type']&.to_sym, format: schema['format']&.to_sym,
        transformation: nil, default: schema['default']
      )
    end

    def build_body_field(name, field_schema, override, context)
      money = resolve_field_money(name, field_schema, context)
      build_field_ir(name, field_schema, override, context, money)
    end

    def resolve_field_money(name, field_schema, context)
      money = @money_resolver.call(
        field_name: name, field_schema: field_schema, operation_mapping: context.fetch(:mapping_entry),
        diagnostics: context.fetch(:diagnostics), operation_id: context.fetch(:operation_id)
      )
      context.fetch(:money_transformations) << money.fetch(:entry) if money
      money
    end

    def build_field_ir(name, field_schema, override, context, money)
      FieldIR.new(
        source_name: name, target_name: override&.fetch('target', name) || name, location: :body,
        required: field_required?(override, context.fetch(:required), name),
        nullable: field_schema['nullable'] == true, type: field_schema['type']&.to_sym,
        format: field_schema['format']&.to_sym, transformation: money&.fetch(:transformation),
        default: field_schema['default']
      )
    end

    def field_required?(override, required, name)
      return override['required'] if override&.key?('required')

      required.include?(name)
    end
  end
end
