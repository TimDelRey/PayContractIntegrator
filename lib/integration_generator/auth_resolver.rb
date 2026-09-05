# frozen_string_literal: true

module IntegrationGenerator
  # Resolves which security scheme an operation actually uses. A single
  # alternative is taken as-is; multiple alternatives need a mapping
  # override to disambiguate; unsupported scheme types (oauth2, etc.) are
  # out of the V1 support matrix. Either failure drops the operation with a
  # :warning rather than guessing which header to send.
  class AuthResolver
    def call(operation:, security_schemes:, mapping:, diagnostics:)
      return nil if operation[:security].empty?

      candidates = matching_schemes(operation, security_schemes)
      chosen = pick(candidates, mapping)

      return ambiguous!(operation, diagnostics) if ambiguous?(chosen, candidates)
      return unsupported!(operation, diagnostics) if unsupported?(chosen)

      { type: chosen[:type], location: chosen[:location], name: chosen[:scheme_name] }.freeze
    end

    private

    def matching_schemes(operation, security_schemes)
      scheme_names = operation[:security].flat_map(&:keys)
      security_schemes.select { |scheme| scheme_names.include?(scheme[:name]) }
    end

    def ambiguous?(chosen, candidates)
      chosen.nil? && candidates.size > 1
    end

    def unsupported?(chosen)
      chosen.nil? || chosen[:type] == :unsupported
    end

    def pick(candidates, mapping)
      return candidates.first if candidates.size <= 1

      override_name = mapping && mapping['auth_scheme']
      override_name && candidates.find { |candidate| candidate[:name] == override_name }
    end

    def ambiguous!(operation, diagnostics)
      diagnostics << Diagnostic.new(
        severity: :warning,
        code: :ambiguous_auth_scheme,
        message: "#{operation[:id]} has multiple possible auth schemes and none was selected",
        source_path: security_path(operation),
        hint: 'Add an auth_scheme override in integration_mapping.yml'
      )
      :unresolved
    end

    def unsupported!(operation, diagnostics)
      diagnostics << Diagnostic.new(
        severity: :warning,
        code: :unsupported_auth_scheme,
        message: "#{operation[:id]} does not use a supported auth scheme",
        source_path: security_path(operation),
        hint: 'Only apiKey and http basic/bearer schemes are supported in V1'
      )
      :unresolved
    end

    def security_path(operation)
      "#/paths/#{escape(operation[:path])}/#{operation[:method]}/security"
    end

    def escape(path)
      path.to_s.gsub('~', '~0').gsub('/', '~1')
    end
  end
end
