# frozen_string_literal: true

module IntegrationGenerator
  class IrBuilder
    ADAPTER_CONTRACT_VERSION = '1'

    def call(parsed:, resolved:, mapping:, provider_key:, source_name:)
      fields = identity(provider_key).merge(from_resolved(resolved))
      fields.merge!(derived(parsed, resolved, mapping, source_name))
      Generator::IntegrationIR.new(**fields)
    end

    private

    def identity(provider_key)
      {
        contract_version: '1.0', provider_key:,
        provider_class: "#{camelize(provider_key)}Service", env_prefix: provider_key.upcase
      }
    end

    def from_resolved(resolved)
      {
        auth_schemes: resolved.fetch(:auth_schemes), operations: resolved.fetch(:operations),
        webhooks: resolved.fetch(:webhooks), status_map: resolved.fetch(:status_map),
        error_map: resolved.fetch(:error_map), money_transformations: resolved.fetch(:money_transformations)
      }
    end

    def derived(parsed, resolved, mapping, source_name)
      {
        base_urls: parsed.base_urls,
        idempotency: resolve_top_level_idempotency(resolved.fetch(:operations)),
        configuration: build_configuration(resolved.fetch(:auth_schemes)),
        source_metadata: build_source_metadata(parsed, mapping, source_name)
      }
    end

    def camelize(provider_key)
      provider_key.to_s.split(/[_-]/).reject(&:empty?).map { |part| part[0].upcase + part[1..] }.join
    end

    def resolve_top_level_idempotency(operations)
      operation = operations.find { |op| op.role == :create_request && op.idempotency.any? }
      return {}.freeze unless operation

      {
        operation_id: operation.id,
        location: operation.idempotency.fetch(:location),
        name: operation.idempotency.fetch(:name)
      }.freeze
    end

    def build_configuration(auth_schemes)
      configuration = ['base_url']
      configuration.unshift('api_key') if auth_schemes.any? { |scheme| scheme[:type] == :api_key }
      configuration.freeze
    end

    def build_source_metadata(parsed, mapping, source_name)
      {
        name: source_name,
        openapi: parsed.version,
        mapping_name: mapping ? 'integration_mapping.yml' : nil,
        mapping_schema_version: mapping ? mapping['schema_version'] : nil,
        adapter_contract_version: ADAPTER_CONTRACT_VERSION
      }.freeze
    end
  end
end
