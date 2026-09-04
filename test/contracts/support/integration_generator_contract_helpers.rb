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
      base_urls: [ "https://sandbox.example.test/v1" ],
      auth_schemes: [ { type: :api_key, location: :header, name: "X-API-Key" } ],
      operations: [ operation_ir ],
      webhooks: [],
      status_map: { "pending" => "in_progress", "completed" => "approved" },
      error_map: { "validation_error" => "validation_error" },
      money_transformations: [ { field: "amount", from: "rub", to: "kopeck", multiplier: 100 } ],
      configuration: [ "api_key", "base_url" ],
      source_metadata: { name: "provider_api.yaml", openapi: "3.1.0" }
    )
  end

  def operation_ir
    IntegrationGenerator::OperationIR.new(
      id: "createPayout",
      role: :create_request,
      method: :post,
      path: "/payouts",
      parameters: [],
      request_fields: [
        IntegrationGenerator::FieldIR.new(
          source_name: "amount",
          target_name: "amount",
          location: :body,
          required: true,
          nullable: false,
          type: :integer,
          format: nil,
          transformation: :rub_to_kopeck,
          default: nil
        )
      ],
      responses: [ { status: 201, schema: "Payout", example: { "id" => "np_test", "status" => "pending" } } ],
      idempotency: { location: :header, name: "Idempotency-Key" }
    )
  end

  def minimal_spec
    <<~YAML
      openapi: 3.1.0
      info:
        title: NovaPay
        version: 1.0.0
      servers:
        - url: https://sandbox.example.test/v1
      paths:
        /payouts:
          post:
            operationId: createPayout
            x-integration-role: create_request
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
      components:
        securitySchemes:
          ApiKeyAuth:
            type: apiKey
            in: header
            name: X-API-Key
    YAML
  end
end
