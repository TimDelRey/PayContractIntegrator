module IntegrationGeneratorContractHelpers
  def diagnostic(severity: :warning, code: :optional_description_missing)
    IntegrationGenerator::Diagnostic.new(
      severity: severity,
      code: code,
      message: "Description is missing",
      source_path: "#/paths/~1payouts/post",
      hint: "Add description"
    )
  end

  def integration_ir
    IntegrationGenerator::IntegrationIR.new(
      schema_version: "1.0",
      provider_key: "novapay",
      provider_class: "NovapayService",
      env_prefix: "NOVAPAY",
      base_urls: deeply_frozen([ "https://sandbox.example.test/v1" ]),
      auth_schemes: deeply_frozen([ { type: :api_key, location: :header, name: "X-API-Key" } ]),
      operations: deeply_frozen([ operation_ir ]),
      webhooks: deeply_frozen([]),
      status_map: deeply_frozen({ "pending" => "in_progress", "completed" => "approved" }),
      error_map: deeply_frozen({ "validation_error" => "validation_error" }),
      money_transformations: deeply_frozen([
        { field: "amount", from: "rub", to: "kopeck", multiplier: 100, rounding: :exact }
      ]),
      idempotency: deeply_frozen({ operation_id: "createPayout", location: :header, name: "Idempotency-Key" }),
      configuration: deeply_frozen([ "api_key", "base_url" ]),
      source_metadata: deeply_frozen({
        name: "provider_api.yaml",
        openapi: "3.1.0",
        mapping_name: "integration_mapping.yml",
        mapping_schema_version: "1.0",
        adapter_contract_version: "1"
      })
    )
  end

  def operation_ir
    IntegrationGenerator::OperationIR.new(
      id: "createPayout",
      role: :create_request,
      method: :post,
      path: "/payouts",
      parameters: deeply_frozen([]),
      request_fields: deeply_frozen([
        IntegrationGenerator::FieldIR.new(
          source_name: "amount",
          target_name: "amount",
          location: :body,
          required: true,
          nullable: false,
          type: :integer,
          format: :int64,
          transformation: :rub_to_kopeck,
          default: nil
        )
      ]),
      responses: deeply_frozen([
        { status: 201, schema: "Payout", example: { "id" => "np_test", "status" => "pending" } },
        { status: 422, schema: "ProviderError", example: { "error" => { "code" => "validation_error" } } }
      ]),
      idempotency: deeply_frozen({ location: :header, name: "Idempotency-Key" })
    )
  end

  def minimal_spec
    <<~YAML
      openapi: 3.1.0
      info:
        title: Synthetic Payments API
        version: 1.0.0
      servers:
        - url: https://sandbox.example.test/v1
      paths:
        /payouts:
          post:
            operationId: createPayout
            security:
              - ApiKeyAuth: []
            requestBody:
              required: true
              content:
                application/json:
                  schema:
                    type: object
                    required: [amount]
                    properties:
                      amount: { type: integer, format: int64 }
            responses:
              "201":
                description: Created
              "422":
                description: Invalid request
      components:
        securitySchemes:
          ApiKeyAuth:
            type: apiKey
            in: header
            name: X-API-Key
    YAML
  end

  def minimal_mapping
    <<~YAML
      schema_version: "1.0"
      operations:
        - operation_id: createPayout
          role: create_request
          fields:
            amount:
              target: amount
              required: true
              nullable: false
          money:
            field: amount
            from: rub
            to: kopeck
            multiplier: 100
            rounding: exact
          idempotency:
            location: header
            name: Idempotency-Key
      status_map:
        pending: in_progress
        completed: approved
      error_map:
        validation_error: validation_error
      configuration:
        - api_key
        - base_url
    YAML
  end

  # A single operation that does not match any of SemanticResolver's role
  # heuristics (not POST-with-body, not GET-with-id-param, no /cancel
  # suffix, no webhook signal) -- analogous to NovaPay's real getBalance.
  def spec_with_unclassifiable_operation
    <<~YAML
      openapi: 3.0.3
      info:
        title: Synthetic Payments API
        version: 1.0.0
      servers:
        - url: https://sandbox.example.test/v1
      paths:
        /balance:
          get:
            operationId: getBalance
            security:
              - ApiKeyAuth: []
            responses:
              "200":
                description: OK
      components:
        securitySchemes:
          ApiKeyAuth:
            type: apiKey
            in: header
            name: X-API-Key
    YAML
  end

  private

  def deeply_frozen(value)
    case value
    when Hash
      value.each { |key, nested| deeply_frozen(key); deeply_frozen(nested) }
    when Array
      value.each { |nested| deeply_frozen(nested) }
    end
    value.freeze
  end
end
