# frozen_string_literal: true

module IntegrationGenerator
  # Resolves which security scheme an operation actually uses. Real specs
  # routinely offer alternatives where only one is actually supported (e.g.
  # "apiKey or oauth2") -- that is not ambiguous, since only one candidate
  # could ever be chosen. Genuine ambiguity is when 2+ *supported* schemes
  # remain and nothing picks between them; that needs a mapping override
  # rather than an arbitrary guess at which header to send.
  class AuthResolver
    def call(operation:, security_schemes:, mapping:, diagnostics:)
      return nil if operation[:security].empty?

      supported = supported_schemes(operation, security_schemes)
      return unsupported!(operation, diagnostics) if supported.empty?
      return build(supported.first) if supported.size == 1

      chosen = pick(supported, mapping)
      return ambiguous!(operation, diagnostics) unless chosen

      build(chosen)
    end

    private

    def supported_schemes(operation, security_schemes)
      scheme_names = operation[:security].flat_map(&:keys)
      security_schemes.select { |scheme| scheme_names.include?(scheme[:name]) && scheme[:type] != :unsupported }
    end

    def pick(supported, mapping)
      override_name = mapping && mapping['auth_scheme']
      override_name && supported.find { |candidate| candidate[:name] == override_name }
    end

    def build(scheme)
      { type: scheme[:type], location: scheme[:location], name: scheme[:scheme_name] }.freeze
    end

    def ambiguous!(operation, diagnostics)
      diagnostics << Generator::Diagnostic.new(
        severity: :warning,
        code: :ambiguous_auth_scheme,
        message: "#{operation[:id]} has multiple possible auth schemes and none was selected",
        source_path: security_path(operation),
        hint: 'Add an auth_scheme override in integration_mapping.yml'
      )
      :unresolved
    end

    def unsupported!(operation, diagnostics)
      diagnostics << Generator::Diagnostic.new(
        severity: :warning,
        code: :unsupported_auth_scheme,
        message: "#{operation[:id]} does not use a supported auth scheme",
        source_path: security_path(operation),
        hint: 'Only apiKey and http Bearer schemes are supported in V1'
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
