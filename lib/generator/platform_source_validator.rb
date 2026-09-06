module Generator
  # Structural checks for FieldIR#platform_source and FieldIR#required_if,
  # split out of ServiceValidator to keep that class under the shared
  # Metrics/ClassLength budget. Both values get embedded literally into the
  # generated service by Handlers::FieldRenderer, so this is a security
  # boundary, not just a shape check: every kind's payload data and
  # required_if.condition.equals must be safe scalars, never an arbitrary
  # object whose #inspect could inject code into the rendered source
  # (mirrors ServiceValidator#check_map's guard for status_map/error_map).
  class PlatformSourceValidator
    KINDS = %i[constant attribute requisite_container unknown].freeze

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

    # A required field with no resolved read path would ship a payload
    # silently missing that field -- AGENTS.md forbids emitting plausible
    # incomplete code for unresolved required payment semantics, so this is
    # a generation error, not a warning.
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

    # required_if only makes sense on an :attribute field: it guards
    # whether that field's own value (read via operation.public_send) is
    # present, so a field with no computable read expression (:unknown,
    # :constant, :requisite_container) or one that's already unconditionally
    # required can't carry it. condition.field must also name a sibling
    # :attribute field, since FieldRenderer renders the guard as
    # operation.public_send(that sibling's platform attribute).
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
