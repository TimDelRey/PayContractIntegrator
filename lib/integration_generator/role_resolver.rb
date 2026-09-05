# frozen_string_literal: true

module IntegrationGenerator
  # Determines an operation's BaseService role: a mapping override, then an
  # x-space-payments-role extension, then a structural heuristic.
  #
  # The heuristic first picks *one* resource -- the create_request candidate
  # -- out of possibly many unrelated POST endpoints in a multi-resource API
  # (a merchant platform exposes checkouts, customers, readers... only one
  # of those is the payment flow we care about). It then scopes
  # fetch_status/cancel to operations under that same resource path. A bare
  # "GET with an id param" is not enough on its own -- that matches almost
  # any REST "get by id" endpoint, payment-related or not.
  class RoleResolver
    PAYMENT_KEYWORDS = /payout|payment|disburs|transfer|payin|checkout|charge|withdraw/i
    SIGNATURE_NAME_PATTERN = /signature|подпис/i

    Context = Struct.new(:resource_prefix, :diagnostics, keyword_init: true)

    def build_context(operations:, mapping:)
      candidates = create_candidates(operations)
      resource = mapping_assigned_resource(operations, mapping) || choose_resource(candidates)

      Context.new(resource_prefix: resource&.fetch(:path), diagnostics: context_diagnostics(resource, candidates))
    end

    def call(operation:, mapping_entry:, context:)
      return mapping_entry['role'].to_sym if mapping_entry && mapping_entry['role']

      extension_role = operation[:extensions]['x-space-payments-role']
      return extension_role.to_sym if extension_role

      heuristic(operation, context)
    end

    private

    # -- resource selection (which endpoint family is "the" payment flow) --

    def create_candidates(operations)
      operations.select { |operation| create_shaped?(operation) }
    end

    def create_shaped?(operation)
      return false if webhook?(operation)

      operation[:method] == :post && !id_param?(operation[:path]) && operation[:request_body_schema]
    end

    def mapping_assigned_resource(operations, mapping)
      return nil unless mapping

      entry = Array(mapping['operations']).find { |op| op['role'] == 'create_request' }
      entry && operations.find { |operation| operation[:id] == entry['operation_id'] }
    end

    def choose_resource(candidates)
      return nil if candidates.empty?
      return candidates.first if candidates.size == 1

      matches = candidates.select { |operation| payment_keyword?(operation) }
      matches.size == 1 ? matches.first : nil
    end

    # Deliberately excludes the free-text description: real specs routinely
    # mention "payment" in passing on unrelated resources (e.g. a customer
    # endpoint that talks about "payment instruments"), which produced false
    # matches. Path/summary/tags are short, curated fields where the word
    # actually names what the resource is.
    def payment_keyword?(operation)
      haystack = [operation[:path], operation[:summary], *operation[:tags]].compact.join(' ')
      haystack.match?(PAYMENT_KEYWORDS)
    end

    def context_diagnostics(resource, candidates)
      return [] if resource || candidates.size <= 1

      [ambiguous_resource_diagnostic(candidates)]
    end

    def ambiguous_resource_diagnostic(candidates)
      paths = candidates.map { |operation| "#{operation[:method].to_s.upcase} #{operation[:path]}" }.join(', ')
      Diagnostic.new(
        severity: :warning,
        code: :ambiguous_payment_resource,
        message: "Multiple candidate create operations found (#{paths}) and none could be prioritized",
        source_path: '#/paths',
        hint: 'Add an operation entry with role: create_request in integration_mapping.yml to pick one'
      )
    end

    # -- per-operation role heuristic --

    def heuristic(operation, context)
      return :cancel if cancel?(operation, context)
      return :webhook if webhook?(operation)
      return :create_request if create_request?(operation, context)
      return :fetch_status if fetch_status?(operation, context)

      nil
    end

    def cancel?(operation, context)
      operation[:method] == :post && operation[:path].match?(%r{/cancel\z}) && under_resource?(operation, context)
    end

    def webhook?(operation)
      operation[:path].start_with?('/webhooks') || webhook_signal?(operation)
    end

    def create_request?(operation, context)
      context.resource_prefix && operation[:method] == :post && operation[:path] == context.resource_prefix
    end

    def fetch_status?(operation, context)
      operation[:method] == :get && id_param?(operation[:path]) && under_resource?(operation, context)
    end

    def under_resource?(operation, context)
      prefix = context.resource_prefix
      return false unless prefix

      path = operation[:path]
      path == prefix || path.start_with?("#{prefix}/")
    end

    def id_param?(path)
      path.match?(/\{[^}]+\}/)
    end

    def webhook_signal?(operation)
      operation[:security].empty? && operation[:parameters].any? { |p| p['name'].to_s.match?(SIGNATURE_NAME_PATTERN) }
    end
  end
end
