module Generator
  class IrAdapter
    def call(ir:)
      return unsupported_webhooks(ir) if ir.webhooks.any?

      CompileResult.new(ir: build_ir(ir), diagnostics: [])
    end

    private

    def build_ir(ir)
      IntegrationIR.new(
        contract_version: ir.schema_version,
        provider_key: ir.provider_key,
        provider_class: ir.provider_class,
        env_prefix: ir.env_prefix,
        base_urls: ir.base_urls,
        auth_schemes: ir.auth_schemes,
        operations: ir.operations.map { |operation| adapt_operation(operation) },
        webhooks: [],
        status_map: ir.status_map,
        error_map: ir.error_map,
        money_transformations: ir.money_transformations,
        idempotency: ir.idempotency || {},
        configuration: ir.configuration,
        source_metadata: ir.source_metadata
      )
    end

    def adapt_operation(operation)
      OperationIR.new(
        id: operation.id,
        role: operation.role,
        method: operation.method,
        path: operation.path,
        parameters: operation.parameters,
        request_fields: operation.request_fields.map { |field| adapt_field(field) },
        responses: operation.responses,
        idempotency: operation.idempotency || {}
      )
    end

    def adapt_field(field)
      FieldIR.new(
        source_name: field.source_name,
        target_name: field.target_name,
        location: field.location,
        required: field.required,
        nullable: field.nullable,
        type: field.type,
        format: field.format,
        transformation: field.transformation,
        default: field.default
      )
    end

    def unsupported_webhooks(ir)
      CompileResult.new(ir: nil, diagnostics: [unsupported_webhooks_diagnostic(ir)])
    end

    def unsupported_webhooks_diagnostic(ir)
      Diagnostic.new(
        severity: :error,
        code: :webhook_contract_unsupported,
        message: "#{ir.webhooks.map(&:id).join(', ')} resolved as webhook(s), but the Spec Compiler cannot yet " \
                 'supply a signature secret, encoding, signed payload, or event map for them',
        source_path: ir.webhooks.first.path,
        hint: 'Add a webhook override (secret_env, encoding, signed_payload, event_map) in ' \
              'integration_mapping.yml, or remove the webhook operation before generating'
      )
    end
  end
end
