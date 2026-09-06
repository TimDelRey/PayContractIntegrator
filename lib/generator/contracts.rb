module Generator
  IR_CONTRACT_VERSION = '1.0'.freeze
  RESULT_CONTRACT_VERSION = '1.0'.freeze
  EXAMPLES_CONTRACT_VERSION = '1.0'.freeze
  GUIDE_PATH = 'INTEGRATION.md'.freeze
  EXAMPLES_PATH = 'fixtures.json'.freeze
  FILE_TYPES = %i[service guide examples].freeze
  OPERATION_ROLES = %i[check_conditions create_request fetch_status process_callback cancel].freeze
  WEBHOOK_SIGNATURE_FIELDS = %i[algorithm encoding header secret_env signed_payload].freeze
  OPERATION_ROLE_NAMES = OPERATION_ROLES.map(&:to_s).freeze

  # Shared between PlatformFieldResolver (producer) and PlatformSourceValidator (consumer).
  PLATFORM_ATTRIBUTE_ID = 'id'.freeze
  PLATFORM_ATTRIBUTE_AMOUNT = 'amount'.freeze
  PLATFORM_ATTRIBUTES = [PLATFORM_ATTRIBUTE_ID, PLATFORM_ATTRIBUTE_AMOUNT].freeze

  module ImmutableValue
    private

    def deep_freeze(value)
      case value
      when Hash then value.each do |key, item|
        deep_freeze(key)
        deep_freeze(item)
      end
      when Array then value.each { |item| deep_freeze(item) }
      end
      value.freeze
    end
  end

  Diagnostic = Data.define(
    :severity,
    :code,
    :message,
    :source_path,
    :hint
  ) do
    include ImmutableValue

    def initialize(**attributes) = super(**attributes.transform_values { |value| deep_freeze(value) })
  end

  CompileResult = Data.define(
    :ir,
    :diagnostics
  ) do
    include ImmutableValue

    def initialize(ir:, diagnostics:) = super(ir:, diagnostics: deep_freeze(diagnostics))
  end

  # required_if: optional {field:, condition: {field:, equals:}} -- a generic
  # cross-field conditional-requirement rule (e.g. "bank_code required when
  # type equals sbp"). Never provider-name-branched; comes only from a
  # mapping override, defaults to nil (unconditionally required/optional as
  # per `required`).
  #
  # platform_source: how generated code must actually read this field's
  # value off the platform's internal `operation` object (only operation.id/
  # operation.amount/operation.payout_requisite are guaranteed to exist --
  # a field name matching the OpenAPI schema is not itself a valid read
  # path). One of:
  #   {kind: :constant, value:}                      -- fixed, single-enum value
  #   {kind: :attribute, attribute:}                  -- "id" or "amount"
  #   {kind: :requisite_container, requisite_type:, known_keys:, unknown_keys:}
  #   {kind: :unknown}                                -- default; never guessed
  FieldIR = Data.define(
    :source_name,
    :target_name,
    :location,
    :required,
    :nullable,
    :type,
    :format,
    :transformation,
    :default,
    :required_if,
    :platform_source
  ) do
    include ImmutableValue

    def initialize(required_if: nil, platform_source: { kind: :unknown }.freeze, **attributes)
      super(
        required_if: deep_freeze(required_if), platform_source: deep_freeze(platform_source),
        **attributes.transform_values { |value| deep_freeze(value) }
      )
    end
  end

  OperationIR = Data.define(
    :id,
    :role,
    :method,
    :path,
    :parameters,
    :request_fields,
    :responses,
    :idempotency
  ) do
    include ImmutableValue

    def initialize(**attributes) = super(**attributes.transform_values { |value| deep_freeze(value) })
  end

  IntegrationIR = Data.define(
    :contract_version,
    :provider_key,
    :provider_class,
    :env_prefix,
    :base_urls,
    :auth_schemes,
    :operations,
    :webhooks,
    :status_map,
    :error_map,
    :money_transformations,
    :idempotency,
    :configuration,
    :source_metadata
  ) do
    include ImmutableValue

    def initialize(**attributes) = super(**attributes.transform_values { |value| deep_freeze(value) })
  end

  GenerationInput = Data.define(
    :ir,
    :output,
    :force
  )

  GeneratedFile = Data.define(
    :type,
    :relative_path,
    :content,
    :checksum
  )

  Result = Data.define(
    :service,
    :guide,
    :examples,
    :service_path,
    :provider_class,
    :operation_roles,
    :manifest
  )
end
