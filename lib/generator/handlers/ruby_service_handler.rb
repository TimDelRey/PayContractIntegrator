module Generator
  module Handlers
    class RubyServiceHandler < BaseHandler
      private

      def file_type = :service
      def relative_path(ir) = "#{ir.provider_key}_service.rb"

      def render(ir)
        join_lines(
          '',
          'require "openssl"',
          'require "uri"',
          '',
          'module Provider',
          "  class #{ir.provider_class} < BaseService",
          indent(render_constants(ir), 4),
          '',
          indent(render_operations(ir), 4),
          '',
          '    private',
          '',
          indent(render_helpers(ir), 4),
          '  end',
          'end',
          ''
        )
      end

      def render_constants(ir)
        join_lines(
          "BASE_URL = ENV.fetch(#{env_name(ir, 'BASE_URL').dump}, #{ir.base_urls.first.dump})",
          "STATUS_MAP = #{ir.status_map.inspect}.freeze",
          "ERROR_MAP = #{ir.error_map.inspect}.freeze"
        )
      end

      def render_operations(ir)
        ir.operations.map { |operation| render_operation(operation, ir) }.join("\n\n")
      end

      def render_operation(operation, ir)
        case operation.role
        when :create_request then render_create(operation, ir)
        when :fetch_status then render_status(operation)
        when :check_conditions then "def check_conditions(operation, request_method)\n  super\nend"
        when :cancel then render_cancel(operation)
        when :process_callback then render_callback(ir)
        else invalid!(:unsupported_operation_role, "Unsupported operation role: #{operation.role.inspect}")
        end
      end

      def render_create(operation, ir)
        fields = operation.request_fields.map { |field| render_field(field, operation.request_fields, ir) }.join("\n")
        idempotency = render_idempotency(operation)
        request = format(
          '  response = client.public_send(%<method>s, BASE_URL + build_path(%<path>s, operation), json: payload, headers:)',
          method: operation.method.inspect, path: operation.path.dump
        )
        join_lines(
          'def create_request(operation, _request_method = "create")',
          '  payload = {}',
          fields,
          '  headers = auth_headers',
          idempotency,
          request,
          '  normalize_response(response)',
          'end'
        )
      end

      def render_field(field, fields, ir) = field_renderer.render(field, fields, ir)

      def field_renderer = @field_renderer ||= FieldRenderer.new

      def render_status(operation)
        request = format(
          '  response = client.public_send(%<method>s, BASE_URL + build_path(%<path>s, operation), headers: auth_headers)',
          method: operation.method.inspect, path: operation.path.dump
        )
        join_lines(
          'def fetch_status(operation)',
          request,
          '  success(STATUS_MAP.fetch(response.body.fetch("status")))',
          'end'
        )
      end

      def render_cancel(operation)
        join_lines(
          'def cancel(operation)',
          '  response = client.public_send(',
          "    #{operation.method.inspect},",
          "    BASE_URL + build_path(#{operation.path.dump}, operation),",
          '    headers: auth_headers',
          '  )',
          '  normalize_response(response)',
          'end'
        )
      end

      def render_callback(ir)
        webhook = webhook_contract(ir)
        event_map = fetch(webhook, :event_map)
        result = event_map.empty? ? 'payload' : "#{event_map.inspect}.fetch(payload.fetch(\"event\"))"
        join_lines(
          'def process_callback(raw_body:, headers:, payload:)',
          '  verify_webhook_signature!(raw_body:, headers:)',
          "  success(#{result})",
          'end'
        )
      end

      def render_helpers(ir)
        helpers = [render_auth_headers(ir), render_path_helper, render_response_helper, render_webhook_helpers(ir)]
        helpers.compact.join("\n\n")
      end

      def render_response_helper
        join_lines(
          'def normalize_response(response)',
          '  error_key = response.body.dig("error", "code")',
          '  error_key ||= response.status if response.respond_to?(:status) && ERROR_MAP.key?(response.status)',
          '  return failure(:unprocessable_entity, ERROR_MAP.fetch(error_key)) if error_key',
          '',
          '  success(response.body)',
          'end'
        )
      end

      def render_path_helper
        join_lines(
          'def build_path(template, operation)',
          '  template.gsub(/{([a-z_][a-z0-9_]*)}/) do',
          '    URI.encode_uri_component(operation.public_send(Regexp.last_match(1)).to_s)',
          '  end',
          'end'
        )
      end

      def render_webhook_helpers(ir)
        return unless ir.operations.any? { |operation| operation.role == :process_callback }

        signature = fetch(webhook_contract(ir), :signature)
        header = fetch(signature, :header)
        secret_env = fetch(signature, :secret_env)
        join_lines(
          'def verify_webhook_signature!(raw_body:, headers:)',
          "  received = headers.fetch(#{header.dump})",
          "  expected = OpenSSL::HMAC.hexdigest(\"SHA256\", ENV.fetch(#{secret_env.dump}), raw_body)",
          '  raise SecurityError, "Invalid webhook signature" unless secure_compare(expected, received)',
          'end',
          '',
          'def secure_compare(left, right)',
          '  return false unless left.is_a?(String) && right.is_a?(String) && left.bytesize == right.bytesize',
          '',
          '  left.bytes.zip(right.bytes).reduce(0) { |difference, (a, b)| difference | (a ^ b) }.zero?',
          'end'
        )
      end

      def webhook_contract(ir) = ir.webhooks.first

      def render_auth_headers(ir)
        scheme = ir.auth_schemes.first
        case fetch(scheme, :type)
        when :api_key
          "def auth_headers\n  { #{fetch(scheme, :name).dump} => ENV.fetch(#{env_name(ir, 'API_KEY').dump}) }\nend"
        when :bearer
          "def auth_headers\n  { \"Authorization\" => \"Bearer \#{ENV.fetch(#{env_name(ir, 'TOKEN').dump})}\" }\nend"
        else
          invalid!(:unsupported_auth_scheme, "Unsupported auth scheme: #{fetch(scheme, :type).inspect}")
        end
      end

      def render_idempotency(operation)
        return '' if operation.idempotency.empty?

        name = fetch(operation.idempotency, :name)
        "  headers[#{name.dump}] = operation.idempotency_key"
      end

      def env_name(ir, suffix) = "#{ir.env_prefix}_#{suffix}"
      def fetch(hash, key) = hash.fetch(key) { hash.fetch(key.to_s) }

      def indent(value, width)
        prefix = ' ' * width
        value.lines.map { |line| line.strip.empty? ? line : prefix + line }.join
      end

      def invalid!(code, message) = fail_generation(code, message)
    end
  end
end
