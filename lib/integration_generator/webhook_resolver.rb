# frozen_string_literal: true

module IntegrationGenerator
  class WebhookResolver
    SIGNATURE_NAME_PATTERN = /signature|подпис/i
    SIGNATURE_ALGORITHMS = {
      'HMAC-SHA256' => :hmac_sha256, 'HMAC-SHA1' => :hmac_sha1, 'RSA-SHA256' => :rsa_sha256
    }.freeze
    SUPPORTED_ALGORITHM = :hmac_sha256

    def call(operation:, diagnostics:, provider_key:)
      signature = resolve_signature(operation, provider_key)
      return warn_missing(operation, diagnostics) if signature.nil?
      return warn_unverifiable(operation, diagnostics) if signature == :unresolved

      { signature: signature, event_map: build_event_map(operation, diagnostics) }.freeze
    end

    private

    def resolve_signature(operation, provider_key)
      param = operation[:parameters].find { |p| p['name'].to_s.match?(SIGNATURE_NAME_PATTERN) }
      return nil unless param

      algorithm = detect_algorithm(operation, param)
      return :unresolved unless algorithm == SUPPORTED_ALGORITHM

      {
        algorithm: algorithm, encoding: :hex, signed_payload: :raw_body,
        header: param['name'], secret_env: "#{provider_key.to_s.upcase}_CALLBACK_SECRET"
      }.freeze
    end

    def detect_algorithm(operation, param)
      haystack = "#{operation[:description]} #{param['description']}"
      match = SIGNATURE_ALGORITHMS.find { |name, _| haystack.include?(name) }
      match&.last
    end

    def build_event_map(operation, diagnostics)
      values = Array(operation[:request_body_schema]&.dig('properties', 'event', 'enum'))
      values.each_with_object({}) do |value, map|
        mapped = match_status_vocabulary(value)
        mapped ? map[value] = mapped : diagnostics << unmapped_event_diagnostic(operation, value)
      end.freeze
    end

    def match_status_vocabulary(value)
      haystack = value.to_s.downcase
      StatusErrorResolver::VOCABULARY.find { |word, _| haystack.match?(/\b#{Regexp.escape(word)}\b/) }&.last
    end

    def warn_missing(operation, diagnostics)
      diagnostics << Generator::Diagnostic.new(
        severity: :warning,
        code: :webhook_signature_missing,
        message: "#{operation[:id]} was classified as a webhook, but no signature header was found",
        source_path: "#/paths/#{operation[:path]}/#{operation[:method]}",
        hint: 'Add a signature header parameter, or add a mapping override'
      )
      nil
    end

    def warn_unverifiable(operation, diagnostics)
      diagnostics << Generator::Diagnostic.new(
        severity: :warning,
        code: :webhook_signature_unverifiable,
        message: "#{operation[:id]} looks like a webhook with a signature header, but the algorithm is " \
                 'unrecognized or unsupported (only HMAC-SHA256 is supported)',
        source_path: "#/paths/#{operation[:path]}/#{operation[:method]}",
        hint: 'Document HMAC-SHA256 in the signature header/operation description, or add a mapping override'
      )
      nil
    end

    def unmapped_event_diagnostic(operation, value)
      Generator::Diagnostic.new(
        severity: :warning,
        code: :unmapped_status_value,
        message: "#{operation[:id]} webhook event #{value.inspect} has no known Space Payments mapping",
        source_path: "#/paths/#{operation[:path]}/#{operation[:method]}",
        hint: 'Add it to integration_mapping.yml event_map'
      )
    end
  end
end
