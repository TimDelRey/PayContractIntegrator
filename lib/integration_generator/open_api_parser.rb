# frozen_string_literal: true

module IntegrationGenerator
  # Provisional, internal parsed-spec shape produced by stage 3. Not yet the
  # frozen IntegrationIR/OperationIR contract from dev_plan.md -- that needs
  # role/mapping resolution (stage 4+), which is out of scope here.
  ParsedSpec = Data.define(:version, :base_urls, :security_schemes, :operations, :source_metadata)

  # Stage 3: extracts version, servers, security schemes and operations from
  # an already safe-loaded and $ref-resolved OpenAPI document. Purely
  # structural -- it never infers payment semantics (role, units, statuses).
  class OpenApiParser
    SUPPORTED_VERSION_PATTERN = /\A3\.[01]\./
    # Matches Generator::ServiceValidator::HTTP_METHODS -- options/head/trace
    # are not payment-relevant, so parsing them would only let an operation
    # role resolve to one and fail late, at generation time, on
    # :invalid_http_method instead of never entering the pipeline.
    HTTP_METHODS = %w[get put post delete patch].freeze

    def call(document:, source_name:)
      version = parse_version(document, source_name)
      base_urls, alternate_base_urls = parse_servers(document, source_name)

      ParsedSpec.new(
        version: version,
        base_urls: base_urls.freeze,
        security_schemes: parse_security_schemes(document),
        operations: parse_operations(document),
        source_metadata: { name: source_name, openapi: version, alternate_base_urls: alternate_base_urls.freeze }.freeze
      )
    end

    private

    def parse_version(document, source_name)
      version = document['openapi']
      return version if version.is_a?(String) && version.match?(SUPPORTED_VERSION_PATTERN)

      raise_error(
        code: :unsupported_openapi_version,
        message: "#{source_name} declares unsupported OpenAPI version #{version.inspect}",
        source_path: '#/openapi',
        hint: 'Use an OpenAPI 3.0.x or 3.1.x document'
      )
    end

    def parse_servers(document, source_name)
      servers = Array(document['servers'])
      ensure_servers_present!(servers, source_name)

      urls = servers.each_with_index.map { |server, index| parse_server_url(server, index, source_name) }
      [[urls.first], urls.drop(1)]
    end

    def ensure_servers_present!(servers, source_name)
      return if servers.any?

      raise_error(
        code: :missing_servers, message: "#{source_name} does not declare any servers",
        source_path: '#/servers', hint: 'Add at least one https:// server URL'
      )
    end

    def parse_server_url(server, index, source_name)
      url = server['url']
      return url if url.is_a?(String) && url.start_with?('https://')

      raise_error(
        code: :unsafe_server_scheme, source_path: "#/servers/#{index}/url",
        message: "#{source_name} server ##{index} does not use a literal https:// URL",
        hint: 'Use a literal https:// URL; templated or non-HTTPS servers are not supported'
      )
    end

    def parse_security_schemes(document)
      schemes = document.dig('components', 'securitySchemes') || {}
      schemes.map { |name, scheme| normalize_security_scheme(name, scheme) }.freeze
    end

    def normalize_security_scheme(name, scheme)
      case scheme['type']
      when 'apiKey'
        { name: name, type: :api_key, location: scheme['in']&.to_sym, scheme_name: scheme['name'] }.freeze
      when 'http'
        normalize_http_scheme(name, scheme)
      else
        { name: name, type: :unsupported, location: nil, scheme_name: scheme['type'] }.freeze
      end
    end

    # Only Bearer is renderable downstream (Generator::ServiceValidator only
    # accepts :api_key/:bearer); Basic and any other http scheme are
    # structurally recognized but marked unsupported rather than silently
    # treated as usable and failing later at generation time.
    def normalize_http_scheme(name, scheme)
      if scheme['scheme'].to_s.downcase == 'bearer'
        { name: name, type: :bearer, location: :header, scheme_name: 'Authorization' }.freeze
      else
        { name: name, type: :unsupported, location: nil, scheme_name: "http_#{scheme['scheme']}" }.freeze
      end
    end

    def parse_operations(document)
      operations = []

      (document['paths'] || {}).each do |path, path_item|
        next unless path_item.is_a?(Hash)

        shared_parameters = Array(path_item['parameters'])
        HTTP_METHODS.each do |method|
          operation = path_item[method]
          operations << build_operation(path, method, operation, shared_parameters) if operation.is_a?(Hash)
        end
      end

      operations.freeze
    end

    def build_operation(path, method, operation, shared_parameters)
      base_operation(path, method, operation, shared_parameters).merge(
        request_body_schema: request_body_schema(operation),
        responses: parse_responses(operation['responses']),
        extensions: extensions_for(operation)
      ).freeze
    end

    def base_operation(path, method, operation, shared_parameters)
      {
        id: operation['operationId'], method: method.to_sym, path: path,
        tags: Array(operation['tags']).freeze, summary: operation['summary'],
        description: operation['description'], security: Array(operation['security']).freeze,
        parameters: merge_parameters(shared_parameters, operation['parameters']).freeze
      }
    end

    # OpenAPI lets a Path Item Object declare a parameter once for every
    # method under that path instead of repeating it per operation; an
    # operation-level parameter with the same (name, in) overrides the
    # shared one, but a shared parameter the operation does not repeat
    # still applies.
    def merge_parameters(shared_parameters, own_parameters)
      own = Array(own_parameters)
      own_keys = own.map { |param| [param['name'], param['in']] }
      inherited = shared_parameters.reject { |param| own_keys.include?([param['name'], param['in']]) }
      inherited + own
    end

    def request_body_schema(operation) = operation.dig('requestBody', 'content', 'application/json', 'schema')

    def extensions_for(operation) = operation.select { |key, _| key.start_with?('x-') }.freeze

    def parse_responses(responses)
      Array(responses).map do |status, response|
        { status: status, schema: response.dig('content', 'application/json', 'schema'),
          example: response.dig('content', 'application/json', 'example') }.freeze
      end.freeze
    end

    def raise_error(code:, message:, source_path:, hint:)
      raise SpecError, Generator::Diagnostic.new(
        severity: :error, code: code, message: message, source_path: source_path, hint: hint
      )
    end
  end
end
