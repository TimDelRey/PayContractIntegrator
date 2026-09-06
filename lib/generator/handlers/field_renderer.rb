module Generator
  module Handlers
    # Renders one request_field's payload assignment for RubyServiceHandler,
    # branching on field.platform_source.fetch(:kind) -- only operation.id/
    # operation.amount/operation.payout_requisite are guaranteed to exist on
    # the platform's operation object (per the platform Q&A), so a field with
    # no resolved read path is left as a visible TODO rather than guessed via
    # operation.public_send(source_name), which would raise NoMethodError for
    # anything but amount/id/payout_requisite. See "Unresolved fields" in the
    # generated guide. Split out of RubyServiceHandler to keep that class
    # under the shared Metrics/ClassLength budget.
    class FieldRenderer
      # `fields` is every request_field on the same operation as `field` --
      # needed so a required_if condition can be rendered against its
      # sibling's actual platform attribute, not an arbitrary field name.
      def render(field, fields, ir)
        case field.platform_source.fetch(:kind)
        when :unknown then render_unknown_field(field)
        when :constant then render_constant_field(field)
        when :requisite_container then render_requisite_field(field)
        else render_attribute_field(field, fields, ir)
        end
      end

      private

      def render_unknown_field(field)
        "  # TODO: '#{field.target_name}' has no known platform read path -- " \
          'add an integration_mapping.yml override, or read it manually here (see "Unresolved fields" in INTEGRATION.md)'
      end

      def render_constant_field(field)
        "  payload[#{field.target_name.dump}] = #{field.platform_source.fetch(:value).inspect}"
      end

      # `value` is read once into a local so an optional/conditional field
      # never calls operation.public_send more than once per request.
      def render_attribute_field(field, fields, ir)
        attribute = field.platform_source.fetch(:attribute)
        read = "  value = operation.public_send(#{attribute.dump})"
        transformation = ir.money_transformations.find { |item| fetch(item, :field) == field.source_name }
        expression = transformation ? money_expression('value', transformation) : 'value'
        assignment = "payload[#{field.target_name.dump}] = #{expression}"
        return join_lines(read, "  #{assignment}") if field.required
        return render_conditional_field(field, fields, read, assignment) if field.required_if

        join_lines(read, "  #{assignment} if operation.respond_to?(#{attribute.dump}) && !value.nil?")
      end

      # required_if is a mapping-only {field:, condition: {field:, equals:}}
      # rule (never inferred, never provider-branched): the field is only
      # truly required while the sibling condition field holds that value.
      # PlatformSourceValidator guarantees this field is :attribute (not
      # required: true), and that the condition's sibling field is itself
      # :attribute -- so its platform attribute (not its arbitrary
      # source_name) is what gets embedded in the generated guard.
      def render_conditional_field(field, fields, read, assignment)
        condition = field.required_if.fetch(:condition)
        sibling = fields.find { |candidate| candidate.source_name == condition.fetch(:field) }
        condition_attribute = sibling.platform_source.fetch(:attribute)
        guard = "operation.public_send(#{condition_attribute.dump}) == #{condition.fetch(:equals).inspect}"
        message = "#{field.target_name} is required when #{condition.fetch(:field)} is #{condition.fetch(:equals)}".dump
        join_lines(
          read,
          "  if #{guard} && value.nil?",
          "    return failure(:missing_conditional_field, #{message})",
          '  end',
          "  #{assignment} unless value.nil?"
        )
      end

      # The type-selector key (e.g. "type" => "sbp") is the one property
      # PlatformFieldResolver deliberately excludes from known_keys/
      # unknown_keys -- it is not read off the operation at all, it is the
      # literal requisite_type the resolver already picked. `requisite` is
      # read once into a local so an N-key container never calls
      # operation.payout_requisite more than once per request.
      def render_requisite_field(field)
        source = field.platform_source
        requisite_type = source.fetch(:requisite_type)
        entries = requisite_entries(requisite_type, Array(source.fetch(:known_keys)))
        todos = Array(source.fetch(:unknown_keys)).map { |key| requisite_todo(field, key) }

        join_lines(
          *todos,
          '  requisite = operation.payout_requisite',
          "  payload[#{field.target_name.dump}] = {",
          entries.map { |entry| "    #{entry}" }.join(",\n"),
          '  }'
        )
      end

      # No "type" entry at all when there is no type-selector to pick a
      # value from -- emitting a literal "type" => nil would send a key the
      # target schema never declared.
      def requisite_entries(requisite_type, known_keys)
        entries = known_keys.map { |key| requisite_entry(requisite_type, key) }
        return entries if requisite_type.nil?

        ["\"type\" => #{requisite_type.inspect}"] + entries
      end

      def requisite_entry(requisite_type, key)
        path = [requisite_type, key].compact.map(&:inspect).join(', ')
        "#{key.dump} => requisite&.dig(#{path})"
      end

      def requisite_todo(field, key)
        "  # TODO: '#{field.target_name}.#{key}' has no known platform read path -- add an override or fill this in manually"
      end

      def money_expression(expression, transformation)
        "Integer(#{expression}) * #{fetch(transformation, :multiplier)}"
      end

      def join_lines(*lines) = lines.join("\n")
      def fetch(hash, key) = hash.fetch(key) { hash.fetch(key.to_s) }
    end
  end
end
