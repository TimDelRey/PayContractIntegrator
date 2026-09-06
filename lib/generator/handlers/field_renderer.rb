module Generator
  module Handlers
    class FieldRenderer
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
