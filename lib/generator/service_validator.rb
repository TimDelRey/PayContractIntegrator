module Generator
  class ServiceValidator
    CLASS_NAME = /\A[A-Z][A-Za-z0-9]*\z/
    METHOD_NAME = /\A[a-z_][a-z0-9_]*\z/
    PROVIDER_KEY = /\A[a-z][a-z0-9_]*\z/
    ENV_NAME = /\A[A-Z][A-Z0-9_]*\z/
    HEADER_NAME = /\A[A-Za-z0-9!#$%&'*+.^_`|~-]+\z/
    # TODO(code-review): OpenApiParser (Spec Compiler side) recognizes
    # %w[get put post delete options head patch trace] -- this list is
    # narrower (missing options/head/trace). A role assigned to one of
    # those methods via a mapping/x-space-payments-role override passes
    # every earlier pipeline stage and only fails here, late, with
    # :invalid_http_method. Worth reconciling the two lists (or deciding
    # options/head/trace are out of scope and rejecting them earlier).
    HTTP_METHODS = %i[get post put patch delete].freeze

    def call(ir)
      check_structure(ir)
      check_service(ir)
      check_operations(ir)
      check_money(ir)
      check_webhook(ir)
    rescue KeyError => e
      fail!(:invalid_ir_structure, "Missing IR field #{e.key.inspect}")
    end

    private

    def check_service(ir)
      check_provider(ir)
      check_base_url(ir)
      fail!(:unsupported_auth_alternatives, 'Exactly one auth scheme is required') unless ir.auth_schemes.one?
      check_auth(ir.auth_schemes.first)
      check_map(ir.status_map, :invalid_status_mapping)
      check_map(ir.error_map, :invalid_error_mapping)
    end

    def check_operations(ir)
      check_unique_roles(ir.operations)
      ir.operations.each { |operation| check_operation(operation, ir) }
    end

    def check_structure(ir)
      arrays = [ir.base_urls, ir.auth_schemes, ir.operations, ir.webhooks, ir.money_transformations]
      hashes = [ir.status_map, ir.error_map, ir.source_metadata]
      valid = arrays.all?(Array) && hashes.all?(Hash) && ir.auth_schemes.all?(Hash) &&
              ir.webhooks.all?(Hash) && ir.money_transformations.all?(Hash) &&
              ir.operations.all? { |operation| valid_operation?(operation) }
      fail!(:invalid_ir_structure, 'IR collections have invalid types') unless valid
    end

    def valid_operation?(operation)
      operation.is_a?(OperationIR) && operation.parameters.is_a?(Array) &&
        operation.parameters.all?(Hash) && operation.request_fields.is_a?(Array) &&
        operation.request_fields.all?(FieldIR) && operation.responses.is_a?(Array) &&
        operation.idempotency.is_a?(Hash)
    end

    def check_auth(scheme)
      case read(scheme, :type)
      when :api_key
        valid = read(scheme, :location) == :header && string_matches?(read(scheme, :name), HEADER_NAME)
        fail!(:unsupported_auth_scheme, 'Only named header API keys are supported') unless valid
      when :bearer
        nil
      else
        fail!(:unsupported_auth_scheme, 'Unsupported auth scheme')
      end
    end

    def check_money(ir)
      check_money_rules(ir.money_transformations)
      check_money_fields(ir)
    end

    def check_money_rules(transformations)
      fields = transformations.map { |transformation| read(transformation, :field) }
      fail!(:ambiguous_money_transformation, 'Money transformations must have unique fields') unless fields.uniq == fields

      transformations.each { |transformation| check_money_rule(transformation) }
    end

    def check_money_rule(transformation)
      multiplier = read(transformation, :multiplier)
      valid = string_matches?(read(transformation, :field), METHOD_NAME) && multiplier.is_a?(Integer) && multiplier.positive?
      fail!(:unsupported_money_transformation, 'Money field and positive Integer multiplier are required') unless valid
      fail!(:unsupported_money_rounding, 'Only exact money conversion is supported') unless read(transformation, :rounding) == :exact
    end

    def check_money_fields(ir)
      fields = ir.operations.flat_map(&:request_fields).map(&:source_name)
      ir.money_transformations.each do |transformation|
        field = read(transformation, :field)
        next if fields.include?(field)

        fail!(:unknown_money_field, "Unknown money field #{field}")
      end
    end

    def check_webhook(ir)
      callback = ir.operations.any? { |operation| operation.role == :process_callback }
      return unless callback || ir.webhooks.any?

      fail!(:ambiguous_webhook_contract, 'Exactly one webhook is required for process_callback') unless callback && ir.webhooks.one?

      webhook = ir.webhooks.first
      signature = read(webhook, :signature)
      check_webhook_signature(signature)
      check_map(read(webhook, :event_map), :invalid_webhook_mapping)
    end

    def check_webhook_signature(signature)
      fail!(:missing_webhook_contract, 'Webhook signature metadata must be a Hash') unless signature.is_a?(Hash)
      missing = WEBHOOK_SIGNATURE_FIELDS.reject { |key| signature.key?(key) || signature.key?(key.to_s) }
      fail!(:missing_webhook_contract, 'Missing webhook signature metadata') unless missing.empty?
      return if supported_webhook_signature?(signature)

      fail!(:unsupported_webhook_signature, 'Only HMAC-SHA256 hex over raw_body is supported')
    end

    def supported_webhook_signature?(signature)
      read(signature, :algorithm) == :hmac_sha256 && read(signature, :encoding) == :hex &&
        read(signature, :signed_payload) == :raw_body &&
        string_matches?(read(signature, :header), HEADER_NAME) &&
        string_matches?(read(signature, :secret_env), ENV_NAME)
    end

    def check_provider(ir)
      fail!(:invalid_provider_class, 'Invalid provider class') unless string_matches?(ir.provider_class, CLASS_NAME)
      fail!(:invalid_provider_key, 'Invalid provider key') unless string_matches?(ir.provider_key, PROVIDER_KEY)
      fail!(:invalid_env_prefix, 'Invalid environment prefix') unless string_matches?(ir.env_prefix, ENV_NAME)
    end

    def check_unique_roles(operations)
      roles = operations.map(&:role)
      fail!(:ambiguous_operation_role, 'Each operation role must be unique') unless roles.uniq == roles
    end

    def check_base_url(ir)
      valid = ir.base_urls.one? && string_matches?(ir.base_urls.first, %r{\Ahttps://[^\s]+\z})
      fail!(:invalid_base_url, 'Exactly one literal HTTPS base URL is required') unless valid
    end

    def check_operation(operation, ir)
      fail!(:unsupported_operation_role, 'Unsupported operation role') unless OPERATION_ROLES.include?(operation.role)
      fail!(:invalid_operation_id, 'Invalid operation id') unless string_matches?(operation.id, /\A[A-Za-z][A-Za-z0-9._-]*\z/)
      fail!(:invalid_http_method, 'Unsupported HTTP method') unless HTTP_METHODS.include?(operation.method)
      check_path(operation)
      check_parameters(operation)
      check_fields(operation)
      check_idempotency(operation.idempotency)
      return unless operation.role == :fetch_status && ir.status_map.empty?

      fail!(:missing_status_mapping, 'fetch_status requires an explicit status map')
    end

    def check_path(operation)
      valid = operation.path.is_a?(String) && operation.path.start_with?('/') && !operation.path.include?('..')
      fail!(:invalid_operation_path, 'Operation path must be a safe relative path') unless valid
    end

    def check_parameters(operation)
      names = operation.path.scan(/\{([^}]+)\}/).flatten
      fail!(:invalid_operation_path, 'Invalid path parameter identifier') unless names.all? { |name| METHOD_NAME.match?(name) }
      operation.parameters.each do |parameter|
        location = read(parameter, :location)
        name = read(parameter, :name)
        next if location == :path && names.include?(name)

        fail!(:unsupported_operation_parameter, "Unsupported #{location} parameter: #{name}")
      end
    end

    # TODO(code-review): neither field.platform_source nor field.required_if
    # is inspected here at all -- see the same TODO in
    # RubyServiceHandler#render_field for what they mean and why it matters
    # (an :unknown/:requisite_container field currently sails through this
    # check and gets rendered as a plain attribute read).
    def check_fields(operation)
      operation.request_fields.each do |field|
        valid = string_matches?(field.source_name, METHOD_NAME) && string_matches?(field.target_name, METHOD_NAME)
        fail!(:invalid_field_identifier, 'Invalid generated field identifier') unless valid
      end
    end

    def check_idempotency(settings)
      return if settings.empty?

      valid = read(settings, :location) == :header && string_matches?(read(settings, :name), HEADER_NAME)
      fail!(:unsupported_idempotency, 'Only named idempotency headers are supported') unless valid
    end

    def check_map(mapping, code)
      valid = mapping.is_a?(Hash) && mapping.all? do |from, to|
        (from.is_a?(String) || from.is_a?(Integer)) && to.is_a?(String)
      end
      fail!(code, 'Mapping keys and values must be safe scalar values') unless valid
    end

    def string_matches?(value, pattern) = value.is_a?(String) && pattern.match?(value)
    def read(hash, key) = hash.fetch(key) { hash.fetch(key.to_s) }

    def fail!(code, message)
      raise GenerationError, Diagnostic.new(severity: :error, code:, message:, source_path: nil, hint: nil)
    end
  end
end
