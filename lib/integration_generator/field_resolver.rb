# frozen_string_literal: true

module IntegrationGenerator
  class FieldResolver
    IDEMPOTENCY_NAME_PATTERN = /idempotency/i

    def initialize(money_resolver: MoneyResolver.new, platform_field_resolver: PlatformFieldResolver.new)
      @money_resolver = money_resolver
      @platform_field_resolver = platform_field_resolver
    end

    def parameters(raw_parameters)
      raw_parameters.select { |param| param['in'] == 'path' }.map { |param| build_parameter_hash(param) }
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

    def idempotency(raw_parameters)
      param = raw_parameters.find { |p| p['name'].to_s.match?(IDEMPOTENCY_NAME_PATTERN) }
      return {}.freeze unless param

      { location: param['in']&.to_sym, name: param['name'] }.freeze
    end

    private

    def build_parameter_hash(param)
      schema = param['schema'] || {}
      {
        name: param['name'], location: :path, required: true,
        type: schema['type']&.to_sym, format: schema['format']&.to_sym
      }.freeze
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
      context.fetch(:money_transformations) << normalized_money_entry(name, money) if money
      money
    end

    def normalized_money_entry(name, money)
      money.fetch(:entry).merge(field: normalize_identifier(name)).freeze
    end

    def build_field_ir(name, field_schema, override, context, money)
      Generator::FieldIR.new(
        source_name: normalize_identifier(name), target_name: normalize_identifier(target_name_for(name, override)),
        location: :body, required: field_required?(override, context.fetch(:required), name),
        nullable: field_schema['nullable'] == true, type: field_schema['type']&.to_sym,
        format: field_schema['format']&.to_sym, transformation: money&.fetch(:transformation),
        default: field_schema['default'], required_if: build_required_if(override),
        platform_source: build_platform_source(name, field_schema, override, money, context)
      )
    end

    def build_platform_source(name, field_schema, override, money, context)
      raw = override && override['platform_source']
      return normalize_platform_source(raw) if raw

      @platform_field_resolver.classify(name, field_schema, money: money, diagnostics: context.fetch(:diagnostics))
    end

    def normalize_platform_source(raw)
      {
        kind: raw['kind']&.to_sym, attribute: raw['attribute'], value: raw['value'],
        requisite_type: raw['requisite_type'], known_keys: raw['known_keys'], unknown_keys: raw['unknown_keys']
      }.compact.freeze
    end

    def target_name_for(name, override)
      (override && override['target']) || name
    end

    def field_required?(override, required, name)
      return override['required'] if override&.key?('required')

      required.include?(name)
    end

    def build_required_if(override)
      rule = override && override['required_if']
      return nil unless rule

      condition = rule['condition'] || {}
      { field: rule['field'], condition: { field: condition['field'], equals: condition['equals'] } }.freeze
    end

    def normalize_identifier(name)
      normalized = name.to_s
                       .gsub(/([a-z0-9])([A-Z])/, '\1_\2')
                       .gsub(/[^a-zA-Z0-9]+/, '_')
                       .downcase
                       .gsub(/\A_+|_+\z/, '')
      normalized = "_#{normalized}" if normalized.match?(/\A[0-9]/)
      normalized.empty? ? '_' : normalized
    end
  end
end
