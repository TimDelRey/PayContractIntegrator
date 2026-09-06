module Generator
  class PlatformSourceValidator
    KINDS = %i[constant attribute requisite_container configuration money_container unknown].freeze
    ENV_NAME_PATTERN = /\A[A-Z][A-Z0-9_]*\z/

    def call(field, fields_by_name, &fail_with)
      @fail_with = fail_with
      check_platform_source(field)
      check_required_if(field, fields_by_name)
    end

    private

    def check_platform_source(field)
      source = field.platform_source
      fail!(:invalid_platform_source, 'platform_source must be a Hash with a known kind') unless valid_kind?(source)

      case source.fetch(:kind)
      when :attribute then check_attribute(source)
      when :requisite_container then check_requisite_container(source)
      when :constant then check_constant(source)
      when :configuration then check_configuration(source)
      when :money_container then check_money_container(source)
      when :unknown then check_unknown(field)
      end
    end

    def valid_kind?(source) = source.is_a?(Hash) && KINDS.include?(source[:kind])

    def check_attribute(source)
      return if PLATFORM_ATTRIBUTES.include?(source[:attribute])

      fail!(:invalid_platform_source, 'An :attribute platform_source must read operation.id or operation.amount')
    end

    def check_constant(source)
      return if safe_scalar?(source[:value])

      fail!(:invalid_platform_source, 'A :constant platform_source value must be a safe scalar')
    end

    def check_configuration(source)
      return if source[:name].is_a?(String) && ENV_NAME_PATTERN.match?(source[:name])

      fail!(:invalid_platform_source, 'A :configuration platform_source must name a safe SCREAMING_SNAKE_CASE env variable')
    end

    def check_money_container(source)
      valid = source[:value_key].is_a?(String) && source[:currency_key].is_a?(String) && safe_scalar?(source[:currency])
      return if valid

      fail!(:invalid_platform_source, 'A :money_container platform_source requires String value_key/currency_key and a safe scalar currency')
    end

    def check_unknown(field)
      return unless field.required

      fail!(:invalid_platform_source, 'A required field cannot have an unresolved (:unknown) platform_source')
    end

    def check_requisite_container(source)
      known = source[:known_keys]
      unknown = source[:unknown_keys]
      valid = (source[:requisite_type].nil? || source[:requisite_type].is_a?(String)) &&
              safe_string_array?(known) && safe_string_array?(unknown) && !Array(known).intersect?(Array(unknown))
      fail!(:invalid_platform_source, 'requisite_container requires a String requisite_type and disjoint String key lists') unless valid
    end

    def safe_string_array?(value) = value.is_a?(Array) && value.all?(String)

    def check_required_if(field, fields_by_name)
      rule = field.required_if
      return if rule.nil?

      check_required_if_applicable!(field)
      return if valid_required_if_shape?(rule, fields_by_name)

      fail!(:invalid_required_if, 'required_if must reference known sibling :attribute fields with a safe scalar condition')
    end

    def check_required_if_applicable!(field)
      unless field.platform_source[:kind] == :attribute
        fail!(:invalid_required_if, 'required_if is only supported on :attribute fields -- other kinds have no computable read expression to guard')
      end
      return unless field.required

      fail!(:invalid_required_if, 'required_if cannot combine with required: true -- a field is either unconditionally or conditionally required')
    end

    def valid_required_if_shape?(rule, fields_by_name)
      return false unless rule.is_a?(Hash) && fields_by_name.key?(rule[:field])

      condition = rule[:condition]
      condition.is_a?(Hash) && condition_field_attribute?(condition[:field], fields_by_name) && safe_scalar?(condition[:equals])
    end

    def condition_field_attribute?(name, fields_by_name)
      sibling = fields_by_name[name]
      !sibling.nil? && sibling.platform_source[:kind] == :attribute
    end

    def safe_scalar?(value) = value.is_a?(String) || value.is_a?(Integer) || [true, false].include?(value) || value.is_a?(Symbol)

    def fail!(code, message) = @fail_with.call(code, message)
  end
end
