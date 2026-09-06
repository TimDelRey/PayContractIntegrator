# frozen_string_literal: true

module IntegrationGenerator
  class AuthResolver
    def call(operation:, security_schemes:, mapping:, diagnostics:)
      return nil if operation[:security].empty?

      supported = supported_schemes(operation, security_schemes)
      return unsupported!(operation, diagnostics) if supported.empty?
      return build(supported.first) if supported.size == 1 || equivalent?(supported)

      chosen = pick(supported, mapping)
      return ambiguous!(operation, diagnostics) unless chosen

      build(chosen)
    end

    private

    def supported_schemes(operation, security_schemes)
      scheme_names = operation[:security].flat_map(&:keys)
      security_schemes.select { |scheme| scheme_names.include?(scheme[:name]) && scheme[:type] != :unsupported }
    end

    def equivalent?(supported)
      supported.map { |scheme| build(scheme) }.uniq.size == 1
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

    def security_path(operation) = "#{JsonPointer.operation_path(operation)}/security"
  end
end
