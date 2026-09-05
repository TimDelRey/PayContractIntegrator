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
          event_map = fetch(webhook, :event_map, {})
          # TODO(code-review): event_map.min on an empty Hash returns nil,
          # so event/expected silently become nil here (a webhook whose
          # event values all failed vocabulary matching still passes
          # ServiceValidator#check_webhook, which only checks event_map is
          # a Hash of safe scalars, not that it's non-empty). Consider
          # skipping this example (or failing generation) when event_map
          # is empty instead of emitting {"event": null, "expected": null}.
          event, expected = event_map.min
          { 'name' => "callback_#{index + 1}", 'payload' => { 'event' => event }, 'expected' => expected }
        end
      end

      def fetch(hash, key, default)
        hash.fetch(key) { hash.fetch(key.to_s, default) }
      end
    end
  end
end
