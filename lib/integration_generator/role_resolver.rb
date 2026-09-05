# frozen_string_literal: true

module IntegrationGenerator
  # Determines an operation's BaseService role: a mapping override, then an
  # x-space-payments-role extension, then a structural heuristic. Returns
  # nil (never guesses) when nothing decides it -- the caller treats that
  # as "skip this operation with a warning".
  class RoleResolver
    SIGNATURE_NAME_PATTERN = /signature|подпис/i

    def call(operation:, mapping_entry:)
      return mapping_entry['role'].to_sym if mapping_entry && mapping_entry['role']

      extension_role = operation[:extensions]['x-space-payments-role']
      return extension_role.to_sym if extension_role

      heuristic(operation)
    end

    private

    def heuristic(operation)
      return :cancel if cancel?(operation)
      return :webhook if webhook?(operation)
      return :create_request if create_request?(operation)
      return :fetch_status if fetch_status?(operation)

      nil
    end

    def cancel?(operation)
      operation[:method] == :post && operation[:path].match?(%r{/cancel\z})
    end

    def webhook?(operation)
      operation[:path].start_with?('/webhooks') || webhook_signal?(operation)
    end

    def create_request?(operation)
      operation[:method] == :post && !id_param?(operation[:path]) && operation[:request_body_schema]
    end

    def fetch_status?(operation)
      operation[:method] == :get && id_param?(operation[:path])
    end

    def id_param?(path)
      path.match?(/\{[^}]+\}/)
    end

    def webhook_signal?(operation)
      operation[:security].empty? && operation[:parameters].any? { |p| p['name'].to_s.match?(SIGNATURE_NAME_PATTERN) }
    end
  end
end
