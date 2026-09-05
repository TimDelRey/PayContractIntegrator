module Generator
  IR_CONTRACT_VERSION = '1.0'.freeze
  RESULT_CONTRACT_VERSION = '1.0'.freeze
  EXAMPLES_CONTRACT_VERSION = '1.0'.freeze
  GUIDE_PATH = 'INTEGRATION.md'.freeze
  EXAMPLES_PATH = 'examples.json'.freeze
  FILE_TYPES = %i[service guide examples].freeze
  OPERATION_ROLES = %i[check_conditions create_request fetch_status process_callback cancel].freeze
  WEBHOOK_SIGNATURE_FIELDS = %i[algorithm encoding header secret_env signed_payload].freeze
  OPERATION_ROLE_NAMES = OPERATION_ROLES.map(&:to_s).freeze

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

  FieldIR = Data.define(
    :source_name,
    :target_name,
    :location,
    :required,
    :nullable,
    :type,
    :format,
    :transformation,
    :default
  ) do
    include ImmutableValue

    def initialize(**attributes) = super(**attributes.transform_values { |value| deep_freeze(value) })
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
