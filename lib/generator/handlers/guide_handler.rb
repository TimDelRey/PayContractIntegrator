module Generator
  module Handlers
    class GuideHandler < BaseHandler
      AUTH_FIELDS = %i[type location name].freeze
      IDEMPOTENCY_FIELDS = %i[location name].freeze

      private

      def file_type = :guide
      def relative_path(_ir) = GUIDE_PATH

      def render(ir) = "#{sections(ir).join("\n\n")}\n"

      def sections(ir)
        [
          "# #{title(ir)} Integration",
          source(ir),
          section('Installation', "Install `#{ir.provider_key}_service.rb` as `app/services/provider/#{ir.provider_key}_service.rb`."),
          section('Configuration', configuration(ir)),
          section('Authorization', authorization(ir)),
          section('Operations', operations(ir)),
          section('Status mapping', mapping_table(ir.status_map)),
          section('Error mapping', mapping_table(ir.error_map)),
          section('Webhooks', webhooks(ir)),
          section('Unresolved fields', unresolved_fields(ir)),
          '**Warning:** generated against fallback adapter contract because the host contract was unavailable.',
          "Adapter contract version: `#{ir.source_metadata.fetch(:adapter_contract_version)}`."
        ]
      end

      def section(title, content) = "## #{title}\n\n#{content}"

      def source(ir)
        name = ir.source_metadata.fetch(:name)
        version = ir.source_metadata.fetch(:mapping_schema_version)
        "Generated from `#{name}` using mapping schema `#{version}`."
      end

      def title(ir)
        ir.provider_class.delete_suffix('Service').gsub(/([a-z0-9])([A-Z])/, '\1 \2')
      end

      def configuration(ir)
        variables = ["#{ir.env_prefix}_BASE_URL", auth_variable(ir)]
        variables.concat(ir.webhooks.map { |webhook| value(value(webhook, :signature, {}), :secret_env, nil) })
        variables.compact.uniq.sort.map { |name| "- `#{name}`" }.join("\n")
      end

      def auth_variable(ir)
        suffix = value(ir.auth_schemes.first, :type, nil) == :bearer ? 'TOKEN' : 'API_KEY'
        "#{ir.env_prefix}_#{suffix}"
      end

      def authorization(ir)
        ir.auth_schemes.map { |scheme| "- #{inline_hash(scheme, AUTH_FIELDS)}" }.join("\n")
      end

      def operations(ir)
        ir.operations.map do |operation|
          idempotency = operation.idempotency.empty? ? '' : "; idempotency: #{inline_hash(operation.idempotency, IDEMPOTENCY_FIELDS)}"
          "- `#{operation.role}`: `#{operation.method.to_s.upcase} #{operation.path}`#{idempotency}"
        end.join("\n")
      end

      def mapping_table(mapping)
        return 'Not configured.' if mapping.empty?

        (['| Provider | Application |', '| --- | --- |'] + mapping.sort.map { |from, to| "| `#{from}` | `#{to}` |" }).join("\n")
      end

      def webhooks(ir)
        return 'Not configured.' if ir.webhooks.empty?

        ir.webhooks.map { |webhook| "- signature: #{inline_hash(value(webhook, :signature, {}), WEBHOOK_SIGNATURE_FIELDS)}" }.join("\n")
      end

      def unresolved_fields(ir)
        lines = ir.operations.flat_map { |operation| unresolved_operation_fields(operation) }
        lines.empty? ? 'None.' : lines.join("\n")
      end

      def unresolved_operation_fields(operation)
        operation.request_fields.flat_map { |field| unresolved_field_lines(operation, field) }
      end

      def unresolved_field_lines(operation, field)
        case field.platform_source[:kind]
        when :unknown
          ["- `#{operation.id}`: `#{field.target_name}` -- add an override in `integration_mapping.yml`"]
        when :requisite_container
          Array(field.platform_source[:unknown_keys]).map do |key|
            "- `#{operation.id}`: `#{field.target_name}.#{key}` -- add an override in `integration_mapping.yml`"
          end
        else
          []
        end
      end

      def value(hash, key, default) = hash.fetch(key) { hash.fetch(key.to_s, default) }

      def inline_hash(value, fields = value.keys)
        value = fields.to_h { |key| [key, value[key] || value[key.to_s]] }.compact
        value.sort_by { |key, _| key.to_s }.map { |key, item| "#{key}=#{item}" }.join(', ')
      end
    end
  end
end
