# frozen_string_literal: true

module IntegrationGenerator
  # Structured, immutable diagnostic shared by every pipeline stage. Severity
  # is either :error (blocks generation) or :warning (informational).
  Diagnostic = Data.define(:severity, :code, :message, :source_path, :hint)

  # A single request/response/parameter field, normalized and unit-converted.
  FieldIR = Data.define(
    :source_name, :target_name, :location, :required, :nullable,
    :type, :format, :transformation, :default
  )

  # One BaseService-contract operation (create/status/cancel), already
  # role-resolved. Webhook-role operations live in IntegrationIR#webhooks
  # instead, since they are not called by the service but received by it.
  OperationIR = Data.define(:id, :role, :method, :path, :parameters, :request_fields, :responses, :idempotency)

  # An incoming notification, kept separate from OperationIR because it
  # carries signature-verification metadata instead of request-building info.
  WebhookIR = Data.define(:id, :path, :parameters, :payload_fields, :signature)

  # The frozen boundary between the Spec Compiler (A) and the Artifact
  # Generator (B). Everything B needs to render service/guide/fixtures lives
  # here; B never reads the raw spec or mapping directly.
  IntegrationIR = Data.define(
    :schema_version, :provider_key, :provider_class, :env_prefix, :base_urls,
    :auth_schemes, :operations, :webhooks, :status_map, :error_map,
    :money_transformations, :idempotency, :configuration, :source_metadata
  )

  # Either a usable IR or a set of diagnostics explaining why not -- never
  # both, and never an IR with unresolved error-severity diagnostics behind it.
  CompileResult = Data.define(:ir, :diagnostics)
end
