# frozen_string_literal: true

require 'psych'

module IntegrationGenerator
  class SpecLoader
    MAX_BYTESIZE = 2 * 1024 * 1024
    MAX_NESTING_DEPTH = 64
    PERMITTED_CLASSES = [Date, Time].freeze

    def call(source:, source_name:)
      check_size!(source, source_name)
      document = safe_load(source, source_name)
      check_root!(document, source_name)
      check_nesting!(document, source_name)
      document
    end

    private

    def check_size!(source, source_name)
      return if source.bytesize <= MAX_BYTESIZE

      raise_error(
        code: :input_too_large,
        message: "#{source_name} exceeds the maximum allowed size of #{MAX_BYTESIZE} bytes",
        hint: 'Reduce the specification size or split it into local components'
      )
    end

    def safe_load(source, source_name)
      Psych.safe_load(source, permitted_classes: PERMITTED_CLASSES, aliases: false)
    rescue Psych::AliasesNotEnabled, Psych::DisallowedClass => e
      raise_disallowed_construct(source_name, e)
    rescue Psych::SyntaxError => e
      raise_invalid_yaml(source_name, e)
    end

    def raise_disallowed_construct(source_name, error)
      raise_error(
        code: :disallowed_yaml_construct,
        message: "#{source_name} contains a disallowed YAML construct: #{error.message}",
        hint: 'Use plain YAML scalars, mappings and sequences; remove anchors/aliases and object tags'
      )
    end

    def raise_invalid_yaml(source_name, error)
      raise_error(
        code: :invalid_yaml,
        message: "#{source_name} is not valid YAML: #{error.message}",
        hint: 'Fix the YAML syntax error at the reported line/column'
      )
    end

    def check_root!(document, source_name)
      return if document.is_a?(Hash)

      raise_error(
        code: :invalid_yaml,
        message: "#{source_name} does not have a mapping as its root document",
        hint: 'An OpenAPI document must be a YAML mapping at the root'
      )
    end

    def check_nesting!(node, source_name, depth = 0)
      raise_nesting_error(source_name) if depth > MAX_NESTING_DEPTH

      case node
      when Hash
        node.each_value { |value| check_nesting!(value, source_name, depth + 1) }
      when Array
        node.each { |value| check_nesting!(value, source_name, depth + 1) }
      end
    end

    def raise_nesting_error(source_name)
      raise_error(
        code: :nesting_too_deep,
        message: "#{source_name} exceeds the maximum allowed nesting depth of #{MAX_NESTING_DEPTH}",
        hint: 'Flatten the document or split deeply nested components into local $refs'
      )
    end

    def raise_error(code:, message:, hint:)
      raise SpecError, Generator::Diagnostic.new(severity: :error, code: code, message: message, source_path: '#', hint: hint)
    end
  end
end
