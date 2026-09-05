# frozen_string_literal: true

require 'test_helper'
require 'json'

# rubocop:disable Metrics/ClassLength -- one test class per resolver concern reads better
# than splitting role/money/status/auth/webhook/idempotency coverage across files.
class IntegrationGeneratorSemanticResolverTest < Minitest::Test
  # -- role heuristics ------------------------------------------------------

  test 'resolves create_request for a POST with a body and no id param' do
    resolved = resolve(spec_with_operations(<<~YAML))
      /payouts:
        post:
          operationId: createPayout
          security: [ApiKeyAuth: []]
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { amount: { type: integer } } }
          responses: { "201": { description: Created } }
    YAML

    assert_equal [:create_request], resolved.fetch(:operations).map(&:role)
  end

  test 'resolves fetch_status for a GET with an id path parameter under the payment resource' do
    resolved = resolve(spec_with_operations(<<~YAML))
      /payouts:
        post:
          operationId: createPayout
          security: [ApiKeyAuth: []]
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { amount: { type: integer } } }
          responses: { "201": { description: Created } }
      /payouts/{id}:
        get:
          operationId: getPayoutStatus
          security: [ApiKeyAuth: []]
          parameters:
            - { name: id, in: path, required: true, schema: { type: string } }
          responses: { "200": { description: OK } }
    YAML

    assert_equal %i[create_request fetch_status], resolved.fetch(:operations).map(&:role)
  end

  test 'does not classify an unrelated resource GET-by-id as fetch_status' do
    resolved = resolve(spec_with_operations(<<~YAML))
      /payouts:
        post:
          operationId: createPayout
          security: [ApiKeyAuth: []]
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { amount: { type: integer } } }
          responses: { "201": { description: Created } }
      /persons/{id}:
        get:
          operationId: getPerson
          security: [ApiKeyAuth: []]
          parameters:
            - { name: id, in: path, required: true, schema: { type: string } }
          responses: { "200": { description: OK } }
    YAML

    assert_equal [:create_request], resolved.fetch(:operations).map(&:role)
    diagnostic = resolved.fetch(:diagnostics).find { |d| d.code == :unresolved_operation_role }
    refute_nil diagnostic
  end

  test 'resolves cancel for a POST path ending in /cancel under the payment resource' do
    resolved = resolve(spec_with_operations(<<~YAML))
      /payouts:
        post:
          operationId: createPayout
          security: [ApiKeyAuth: []]
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { amount: { type: integer } } }
          responses: { "201": { description: Created } }
      /payouts/{id}/cancel:
        post:
          operationId: cancelPayout
          security: [ApiKeyAuth: []]
          parameters:
            - { name: id, in: path, required: true, schema: { type: string } }
          responses: { "200": { description: OK } }
    YAML

    assert_equal %i[create_request cancel], resolved.fetch(:operations).map(&:role)
  end

  test 'resolves webhook for a path under /webhooks' do
    resolved = resolve(spec_with_operations(<<~YAML))
      /webhooks/payout:
        post:
          operationId: payoutWebhook
          security: []
          parameters:
            - { name: X-Signature, in: header, required: true, description: "HMAC-SHA256 signature", schema: { type: string } }
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { event: { type: string } } }
          responses: { "200": { description: OK } }
    YAML

    assert_equal 1, resolved.fetch(:webhooks).size
    assert_equal(
      { 'payoutWebhook' => :process_callback },
      resolved.fetch(:operations).to_h { |operation| [operation.id, operation.role] }
    )
  end

  test 'an explicit mapping role overrides what the heuristic would have picked' do
    parsed = parse(spec_with_operations(<<~YAML))
      /payouts/{id}/cancel:
        post:
          operationId: cancelPayout
          security: [ApiKeyAuth: []]
          parameters:
            - { name: id, in: path, required: true, schema: { type: string } }
          responses: { "200": { description: OK } }
    YAML
    mapping = { 'operations' => [{ 'operation_id' => 'cancelPayout', 'role' => 'fetch_status' }] }

    resolved = resolver.call(parsed: parsed, mapping: mapping, provider_key: 'novapay')

    assert_equal [:fetch_status], resolved.fetch(:operations).map(&:role)
  end

  test 'drops an operation with a warning when no heuristic matches' do
    resolved = resolve(spec_with_operations(<<~YAML))
      /balance:
        get:
          operationId: getBalance
          security: [ApiKeyAuth: []]
          responses: { "200": { description: OK } }
    YAML

    assert_empty resolved.fetch(:operations)
    diagnostic = resolved.fetch(:diagnostics).find { |d| d.code == :unresolved_operation_role }
    refute_nil diagnostic
    assert_equal :warning, diagnostic.severity
  end

  test 'picks the payment-keyword-matching resource among several create candidates' do
    resolved = resolve(spec_with_operations(<<~YAML))
      /customers:
        post:
          operationId: createCustomer
          security: [ApiKeyAuth: []]
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { name: { type: string } } }
          responses: { "201": { description: Created } }
      /payouts:
        post:
          operationId: createPayout
          security: [ApiKeyAuth: []]
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { amount: { type: integer } } }
          responses: { "201": { description: Created } }
    YAML

    ids = resolved.fetch(:operations).map(&:id)
    assert_equal ['createPayout'], ids
  end

  test 'reports an ambiguous payment resource when several create candidates share no keyword signal' do
    resolved = resolve(spec_with_operations(<<~YAML))
      /widgets:
        post:
          operationId: createWidget
          security: [ApiKeyAuth: []]
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { name: { type: string } } }
          responses: { "201": { description: Created } }
      /gadgets:
        post:
          operationId: createGadget
          security: [ApiKeyAuth: []]
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { name: { type: string } } }
          responses: { "201": { description: Created } }
    YAML

    assert_empty resolved.fetch(:operations)
    assert_includes resolved.fetch(:diagnostics).map(&:code), :ambiguous_payment_resource
  end

  test 'a mapping-assigned create_request wins the resource even without a keyword match' do
    parsed = parse(spec_with_operations(<<~YAML))
      /widgets:
        post:
          operationId: createWidget
          security: [ApiKeyAuth: []]
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { amount: { type: integer } } }
          responses: { "201": { description: Created } }
      /gadgets:
        post:
          operationId: createGadget
          security: [ApiKeyAuth: []]
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { amount: { type: integer } } }
          responses: { "201": { description: Created } }
      /widgets/{id}:
        get:
          operationId: getWidgetStatus
          security: [ApiKeyAuth: []]
          parameters:
            - { name: id, in: path, required: true, schema: { type: string } }
          responses: { "200": { description: OK } }
    YAML
    mapping = { 'operations' => [{ 'operation_id' => 'createWidget', 'role' => 'create_request' }] }

    resolved = resolver.call(parsed: parsed, mapping: mapping, provider_key: 'novapay')

    assert_equal(
      { 'createWidget' => :create_request, 'getWidgetStatus' => :fetch_status },
      resolved.fetch(:operations).to_h { |operation| [operation.id, operation.role] }
    )
  end

  # -- fields: required_if and identifier normalization -----------------------

  test 'a mapping required_if rule is attached to the field, generic and provider-agnostic' do
    parsed = parse(spec_with_operations(<<~YAML))
      /payouts:
        post:
          operationId: createPayout
          security: [ApiKeyAuth: []]
          requestBody:
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    bank_code: { type: string }
                    type: { type: string }
          responses: { "201": { description: Created } }
    YAML
    mapping = {
      'operations' => [
        { 'operation_id' => 'createPayout',
          'fields' => { 'bank_code' => { 'required_if' => { 'field' => 'bank_code', 'condition' => { 'field' => 'type', 'equals' => 'sbp' } } } } }
      ]
    }

    resolved = resolver.call(parsed: parsed, mapping: mapping, provider_key: 'novapay')

    field = resolved.fetch(:operations).first.request_fields.find { |f| f.source_name == 'bank_code' }
    assert_equal({ field: 'bank_code', condition: { field: 'type', equals: 'sbp' } }, field.required_if)
  end

  test 'normalizes a non-snake_case field name into a valid Ruby identifier' do
    resolved = resolve(spec_with_operations(<<~YAML))
      /payouts:
        post:
          operationId: createPayout
          security: [ApiKeyAuth: []]
          requestBody:
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    externalId: { type: string }
          responses: { "201": { description: Created } }
    YAML

    field = resolved.fetch(:operations).first.request_fields.first
    assert_equal 'external_id', field.source_name
    assert_equal 'external_id', field.target_name
  end

  # -- money ----------------------------------------------------------------

  test 'detects a money unit from a Russian keyword in the field description' do
    resolved = resolve(spec_with_operations(<<~YAML))
      /payouts:
        post:
          operationId: createPayout
          security: [ApiKeyAuth: []]
          requestBody:
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    amount: { type: integer, description: "Сумма в копейках" }
          responses: { "201": { description: Created } }
    YAML

    field = resolved.fetch(:operations).first.request_fields.first
    assert_equal :rub_to_kopeck, field.transformation
    assert_equal({ field: 'amount', from: 'rub', to: 'kopeck', multiplier: 100, rounding: :exact },
                 resolved.fetch(:money_transformations).first)
  end

  test 'a non-snake_case money field name is normalized consistently in source_name and the transformation entry' do
    resolved = resolve(spec_with_operations(<<~YAML))
      /payouts:
        post:
          operationId: createPayout
          security: [ApiKeyAuth: []]
          requestBody:
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    Amount: { type: integer, description: "Сумма в копейках" }
          responses: { "201": { description: Created } }
    YAML

    field = resolved.fetch(:operations).first.request_fields.first
    assert_equal 'amount', field.source_name
    assert_equal 'amount', resolved.fetch(:money_transformations).first.fetch(:field)
  end

  test 'warns and passes the field through unconverted when the unit cannot be determined' do
    resolved = resolve(spec_with_operations(<<~YAML))
      /payouts:
        post:
          operationId: createPayout
          security: [ApiKeyAuth: []]
          requestBody:
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    amount: { type: integer }
          responses: { "201": { description: Created } }
    YAML

    field = resolved.fetch(:operations).first.request_fields.first
    assert_nil field.transformation
    assert_empty resolved.fetch(:money_transformations)
    assert_includes resolved.fetch(:diagnostics).map(&:code), :money_unit_undetermined
  end

  test 'a mapping money override takes priority over description keywords' do
    parsed = parse(spec_with_operations(<<~YAML))
      /payouts:
        post:
          operationId: createPayout
          security: [ApiKeyAuth: []]
          requestBody:
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    amount: { type: integer, description: "Сумма в копейках" }
          responses: { "201": { description: Created } }
    YAML
    mapping = {
      'operations' => [
        { 'operation_id' => 'createPayout',
          'money' => { 'field' => 'amount', 'from' => 'rub', 'to' => 'cent', 'multiplier' => 100,
                       'rounding' => 'exact' } }
      ]
    }

    resolved = resolver.call(parsed: parsed, mapping: mapping, provider_key: 'novapay')

    assert_equal :rub_to_cent, resolved.fetch(:operations).first.request_fields.first.transformation
  end

  # -- status / error vocabulary ---------------------------------------------

  test 'maps known status words through the built-in vocabulary' do
    resolved = resolve(spec_with_status_enum(%w[pending completed failed]))

    assert_equal(
      { 'pending' => 'in_progress', 'completed' => 'approved', 'failed' => 'rejected' },
      resolved.fetch(:status_map)
    )
  end

  test 'warns about a status value with no known mapping' do
    resolved = resolve(spec_with_status_enum(['on_hold']))

    assert_empty resolved.fetch(:status_map)
    assert_includes resolved.fetch(:diagnostics).map(&:code), :unmapped_status_value
  end

  test 'error codes default to an identity mapping' do
    resolved = resolve(spec_with_error_enum(%w[validation_error internal_error]))

    assert_equal({ 'validation_error' => 'validation_error', 'internal_error' => 'internal_error' },
                 resolved.fetch(:error_map))
  end

  # -- auth -------------------------------------------------------------------

  test 'drops an operation when its auth scheme is ambiguous and unresolved' do
    resolved = resolve(spec_with_operations(<<~YAML, security_schemes: two_alternative_schemes))
      /payouts:
        post:
          operationId: createPayout
          security: [SchemeA: [], SchemeB: []]
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { amount: { type: integer } } }
          responses: { "201": { description: Created } }
    YAML

    assert_empty resolved.fetch(:operations)
    assert_includes resolved.fetch(:diagnostics).map(&:code), :ambiguous_auth_scheme
  end

  test 'drops an operation using an unsupported auth scheme type' do
    resolved = resolve(spec_with_operations(<<~YAML, security_schemes: oauth2_scheme))
      /payouts:
        post:
          operationId: createPayout
          security: [OAuth2: []]
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { amount: { type: integer } } }
          responses: { "201": { description: Created } }
    YAML

    assert_empty resolved.fetch(:operations)
    assert_includes resolved.fetch(:diagnostics).map(&:code), :unsupported_auth_scheme
  end

  test 'auto-picks the only supported alternative when other alternatives are unsupported' do
    resolved = resolve(spec_with_operations(<<~YAML, security_schemes: mixed_supported_and_oauth2_schemes))
      /payouts:
        post:
          operationId: createPayout
          security: [ApiKeyAuth: [], OAuth2: []]
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { amount: { type: integer } } }
          responses: { "201": { description: Created } }
    YAML

    assert_equal [:create_request], resolved.fetch(:operations).map(&:role)
    refute_includes resolved.fetch(:diagnostics).map(&:code), :ambiguous_auth_scheme
    refute_includes resolved.fetch(:diagnostics).map(&:code), :unsupported_auth_scheme
  end

  # -- webhook signature --------------------------------------------------------

  test 'recognizes a known webhook signature algorithm' do
    resolved = resolve(spec_with_operations(<<~YAML))
      /webhooks/payout:
        post:
          operationId: payoutWebhook
          security: []
          parameters:
            - { name: X-Signature, in: header, required: true, description: "HMAC-SHA256 signature", schema: { type: string } }
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { event: { type: string } } }
          responses: { "200": { description: OK } }
    YAML

    webhook = resolved.fetch(:webhooks).first
    assert_equal(
      { algorithm: :hmac_sha256, encoding: :hex, signed_payload: :raw_body,
        header: 'X-Signature', secret_env: 'NOVAPAY_CALLBACK_SECRET' },
      webhook.fetch(:signature)
    )
  end

  test 'drops a webhook with a signature header but an unrecognized algorithm' do
    resolved = resolve(spec_with_operations(<<~YAML))
      /webhooks/payout:
        post:
          operationId: payoutWebhook
          security: []
          parameters:
            - { name: X-Signature, in: header, required: true, description: "some proprietary signature", schema: { type: string } }
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { event: { type: string } } }
          responses: { "200": { description: OK } }
    YAML

    assert_empty resolved.fetch(:webhooks)
    assert_includes resolved.fetch(:diagnostics).map(&:code), :webhook_signature_unverifiable
  end

  # -- idempotency ---------------------------------------------------------------

  test 'finds an idempotency parameter by name pattern' do
    resolved = resolve(spec_with_operations(<<~YAML))
      /payouts:
        post:
          operationId: createPayout
          security: [ApiKeyAuth: []]
          parameters:
            - { name: Idempotency-Key, in: header, required: false, schema: { type: string } }
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { amount: { type: integer } } }
          responses: { "201": { description: Created } }
    YAML

    assert_equal({ location: :header, name: 'Idempotency-Key' }, resolved.fetch(:operations).first.idempotency)
  end

  test 'idempotency is empty when no matching parameter exists' do
    resolved = resolve(spec_with_operations(<<~YAML))
      /payouts:
        post:
          operationId: createPayout
          security: [ApiKeyAuth: []]
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { amount: { type: integer } } }
          responses: { "201": { description: Created } }
    YAML

    assert_empty resolved.fetch(:operations).first.idempotency
  end

  private

  def resolver
    IntegrationGenerator::SemanticResolver.new
  end

  def resolve(source, mapping: nil)
    resolver.call(parsed: parse(source), mapping: mapping, provider_key: 'novapay')
  end

  def parse(source, source_name: 'spec.yaml')
    document = IntegrationGenerator::SpecLoader.new.call(source: source, source_name: source_name)
    document = IntegrationGenerator::LocalRefResolver.new.call(document: document, source_name: source_name)
    IntegrationGenerator::OpenApiParser.new.call(document: document, source_name: source_name)
  end

  def two_alternative_schemes
    <<~YAML
      SchemeA:
        type: apiKey
        in: header
        name: X-Scheme-A
      SchemeB:
        type: apiKey
        in: header
        name: X-Scheme-B
    YAML
  end

  def oauth2_scheme
    <<~YAML
      OAuth2:
        type: oauth2
        flows: {}
    YAML
  end

  def mixed_supported_and_oauth2_schemes
    <<~YAML
      ApiKeyAuth:
        type: apiKey
        in: header
        name: X-API-Key
      OAuth2:
        type: oauth2
        flows: {}
    YAML
  end

  def spec_with_operations(paths_yaml, security_schemes: default_security_schemes)
    <<~YAML
      openapi: 3.0.3
      info:
        title: Synthetic Payments API
        version: 1.0.0
      servers:
        - url: https://sandbox.example.test/v1
      paths:
      #{paths_yaml.each_line.map { |line| "  #{line}" }.join}
      components:
        securitySchemes:
      #{security_schemes.each_line.map { |line| "    #{line}" }.join}
    YAML
  end

  def default_security_schemes
    <<~YAML
      ApiKeyAuth:
        type: apiKey
        in: header
        name: X-API-Key
    YAML
  end

  # rubocop:disable Metrics/MethodLength
  def spec_with_status_enum(values)
    spec_with_operations(<<~YAML)
      /payouts/{id}:
        get:
          operationId: getPayoutStatus
          security: [ApiKeyAuth: []]
          parameters:
            - { name: id, in: path, required: true, schema: { type: string } }
          responses:
            "200":
              description: OK
              content:
                application/json:
                  schema:
                    type: object
                    properties:
                      status: { type: string, enum: #{values.to_json} }
    YAML
  end

  def spec_with_error_enum(values)
    spec_with_operations(<<~YAML)
      /payouts:
        post:
          operationId: createPayout
          security: [ApiKeyAuth: []]
          requestBody:
            content:
              application/json:
                schema: { type: object, properties: { amount: { type: integer } } }
          responses:
            "201":
              description: Created
            "422":
              description: Invalid
              content:
                application/json:
                  schema:
                    type: object
                    properties:
                      code: { type: string, enum: #{values.to_json} }
    YAML
  end
  # rubocop:enable Metrics/MethodLength
end
# rubocop:enable Metrics/ClassLength
