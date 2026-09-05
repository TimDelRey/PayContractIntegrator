# frozen_string_literal: true

module IntegrationGenerator
  # Builds a WebhookIR for an operation already classified with role
  # :webhook. Looks for a signature header and a recognized algorithm from
  # a fixed registry -- an unrecognized algorithm drops the webhook with a
  # :warning rather than generating an unverifiable callback; no signature
  # header at all is left unsigned (some providers genuinely do not sign).
  class WebhookResolver
    SIGNATURE_NAME_PATTERN = /signature|подпис/i
    SIGNATURE_ALGORITHMS = {
      'HMAC-SHA256' => :hmac_sha256, 'HMAC-SHA1' => :hmac_sha1, 'RSA-SHA256' => :rsa_sha256
    }.freeze

    def initialize(field_resolver: FieldResolver.new)
      @field_resolver = field_resolver
    end

    def call(operation:, diagnostics:)
      signature = resolve_signature(operation)
      return warn_unverifiable(operation, diagnostics) if signature == :unresolved

      build_webhook(operation, signature, diagnostics)
    end

    private

    def warn_unverifiable(operation, diagnostics)
      diagnostics << unverifiable_diagnostic(operation)
      nil
    end

    def build_webhook(operation, signature, diagnostics)
      WebhookIR.new(
        id: operation[:id], path: operation[:path],
        parameters: @field_resolver.parameters(operation[:parameters]).freeze,
        payload_fields: payload_fields(operation, diagnostics), signature: signature
      )
    end

    def payload_fields(operation, diagnostics)
      @field_resolver.body_fields(
        operation: operation, mapping_entry: nil, diagnostics: diagnostics, money_transformations: []
      ).freeze
    end

    def resolve_signature(operation)
      param = operation[:parameters].find { |p| p['name'].to_s.match?(SIGNATURE_NAME_PATTERN) }
      return nil unless param

      haystack = "#{operation[:description]} #{param['description']}"
      match = SIGNATURE_ALGORITHMS.find { |name, _| haystack.include?(name) }
      return :unresolved unless match

      { header: param['name'], algorithm: match.last }.freeze
    end

    def unverifiable_diagnostic(operation)
      Diagnostic.new(
        severity: :warning,
        code: :webhook_signature_unverifiable,
        message: "#{operation[:id]} looks like a webhook with a signature header, but the algorithm is unrecognized",
        source_path: "#/paths/#{operation[:path]}/#{operation[:method]}",
        hint: 'Document the signature algorithm (e.g. HMAC-SHA256) or add a mapping override'
      )
    end
  end
end
