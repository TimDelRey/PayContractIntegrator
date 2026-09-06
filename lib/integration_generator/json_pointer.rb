# frozen_string_literal: true

module IntegrationGenerator
  module JsonPointer
    module_function

    def escape(token) = token.to_s.gsub('~', '~0').gsub('/', '~1')
    def unescape(token) = token.gsub('~1', '/').gsub('~0', '~')
    def operation_path(operation) = "#/paths/#{escape(operation[:path])}/#{operation[:method]}"
  end
end
