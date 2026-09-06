require 'json'

module Generator
  module Handlers
    class ExamplesHandler < BaseHandler
      SENSITIVE_KEY = /secret|token|password|authorization|api.?key|signature|phone|email|card|account|iban|recipient|customer|name/i

      private

      def file_type = :examples
      def relative_path(_ir) = EXAMPLES_PATH

      def render(ir)
        "#{JSON.pretty_generate(
          'contract_version' => EXAMPLES_CONTRACT_VERSION,
          'provider' => ir.provider_key,
          'base_url' => ir.base_urls.first,
          'operations' => ir.operations.map { |operation| operation_example(operation) },
          'callbacks' => callback_examples(ir)
        )}\n"
      end

      def operation_example(operation)
        {
          'id' => operation.id,
          'role' => operation.role.to_s,
          'request' => synthetic_request(operation),
          'responses' => operation.responses.map { |response| sanitized_response(response) }
        }
      end

      def synthetic_request(operation)
        operation.request_fields.to_h do |field|
          [field.target_name, synthetic_value(field.type, field.target_name)]
        end
      end

      def sanitized_response(response)
        response.to_h.transform_values { |value| sanitize(value) }
      end

      def sanitize(value, key = nil)
        return '[REDACTED]' if key&.match?(SENSITIVE_KEY)

        case value
        when Hash then value.to_h { |nested_key, nested| [nested_key, sanitize(nested, nested_key.to_s)] }
        when Array then value.map { |nested| sanitize(nested) }
        else value
        end
      end

      def synthetic_value(type, name)
        return '[REDACTED]' if name.match?(SENSITIVE_KEY)

        case type
        when :integer then 100
        when :boolean then true
        when :number then '100.00'
        else 'example.test'
        end
      end

      def callback_examples(ir)
        ir.webhooks.map.with_index do |webhook, index|
          event_map = fetch_or(webhook, :event_map, {})
          next if event_map.empty?

          event, expected = event_map.min
          { 'name' => "callback_#{index + 1}", 'payload' => { 'event' => event }, 'expected' => expected }
        end.compact
      end
    end
  end
end
