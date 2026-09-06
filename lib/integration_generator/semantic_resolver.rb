# frozen_string_literal: true

module IntegrationGenerator
  class SemanticResolver
    def initialize(
      role_resolver: RoleResolver.new, field_resolver: FieldResolver.new,
      auth_resolver: AuthResolver.new, webhook_resolver: WebhookResolver.new,
      status_error_resolver: StatusErrorResolver.new
    )
      @role_resolver = role_resolver
      @field_resolver = field_resolver
      @auth_resolver = auth_resolver
      @webhook_resolver = webhook_resolver
      @status_error_resolver = status_error_resolver
    end

    def call(parsed:, mapping:, provider_key:)
      acc = initial_accumulator(parsed, mapping, provider_key)
      parsed.operations.each { |operation| resolve_operation(operation, parsed, acc) }

      status_error = @status_error_resolver.call(
        operations: parsed.operations, mapping: mapping, diagnostics: acc.fetch(:diagnostics)
      )
      build_result(acc, status_error)
    end

    private

    def initial_accumulator(parsed, mapping, provider_key)
      role_context = @role_resolver.build_context(operations: parsed.operations, mapping: mapping)
      {
        mapping: mapping, provider_key: provider_key, role_context: role_context,
        diagnostics: role_context.diagnostics.dup,
        money_transformations: [], auth_schemes: [], operations: [], webhooks: []
      }
    end

    def build_result(acc, status_error)
      {
        operations: acc.fetch(:operations).freeze, webhooks: acc.fetch(:webhooks).freeze,
        auth_schemes: acc.fetch(:auth_schemes).uniq.freeze,
        status_map: status_error.fetch(:status_map), error_map: status_error.fetch(:error_map),
        money_transformations: acc.fetch(:money_transformations).freeze, diagnostics: acc.fetch(:diagnostics)
      }
    end

    def resolve_operation(operation, parsed, acc)
      entry = mapping_entry(acc.fetch(:mapping), operation[:id])
      role = @role_resolver.call(operation: operation, mapping_entry: entry, context: acc.fetch(:role_context))
      return acc.fetch(:diagnostics) << unresolved_role_diagnostic(operation) if role.nil?
      return resolve_webhook(operation, acc) if role == :process_callback

      resolve_regular_operation(operation, role, entry, parsed, acc)
    end

    def resolve_webhook(operation, acc)
      webhook = @webhook_resolver.call(
        operation: operation, diagnostics: acc.fetch(:diagnostics), provider_key: acc.fetch(:provider_key)
      )
      return unless webhook

      acc.fetch(:webhooks) << webhook
      acc.fetch(:operations) << Generator::OperationIR.new(
        id: operation[:id], role: :process_callback, method: operation[:method], path: operation[:path],
        parameters: [].freeze, request_fields: [].freeze, responses: operation[:responses], idempotency: {}.freeze
      )
    end

    def resolve_regular_operation(operation, role, mapping_entry, parsed, acc)
      auth = @auth_resolver.call(
        operation: operation, security_schemes: parsed.security_schemes,
        mapping: acc.fetch(:mapping), diagnostics: acc.fetch(:diagnostics)
      )
      return if auth == :unresolved

      acc.fetch(:auth_schemes) << auth if auth
      acc.fetch(:operations) << build_operation(operation, role, mapping_entry, acc)
    end

    def build_operation(operation, role, mapping_entry, acc)
      parameters = @field_resolver.parameters(operation[:parameters])
      request_fields = @field_resolver.body_fields(
        operation: operation, mapping_entry: mapping_entry,
        diagnostics: acc.fetch(:diagnostics), money_transformations: acc.fetch(:money_transformations)
      )

      Generator::OperationIR.new(
        id: operation[:id], role: role, method: operation[:method], path: operation[:path],
        parameters: parameters.freeze, request_fields: request_fields.freeze,
        responses: operation[:responses], idempotency: @field_resolver.idempotency(operation[:parameters])
      )
    end

    def mapping_entry(mapping, operation_id)
      return nil unless mapping

      Array(mapping['operations']).find { |op| op['operation_id'] == operation_id }
    end

    def unresolved_role_diagnostic(operation)
      Generator::Diagnostic.new(
        severity: :warning,
        code: :unresolved_operation_role,
        message: "Could not determine the role of #{operation[:method].to_s.upcase} #{operation[:path]}; skipped",
        source_path: "#/paths/#{operation[:path]}/#{operation[:method]}",
        hint: 'Add an operation entry with an explicit role in integration_mapping.yml'
      )
    end
  end
end
