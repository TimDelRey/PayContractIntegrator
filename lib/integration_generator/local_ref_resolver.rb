# frozen_string_literal: true

module IntegrationGenerator
  class LocalRefResolver
    MAX_REF_DEPTH = 32

    def call(document:, source_name:)
      @root = document
      @source_name = source_name
      resolve(document, path: '#', stack: [])
    end

    private

    def resolve(node, path:, stack:)
      case node
      when Hash
        node.key?('$ref') ? resolve_ref(node.fetch('$ref'), path: path, stack: stack) : resolve_hash(node, path, stack)
      when Array
        node.each_with_index.map { |value, index| resolve(value, path: "#{path}/#{index}", stack: stack) }
      else
        node
      end
    end

    def resolve_hash(node, path, stack)
      node.each_with_object({}) do |(key, value), result|
        result[key] = resolve(value, path: "#{path}/#{escape(key)}", stack: stack)
      end
    end

    def resolve_ref(ref, path:, stack:)
      ref_path = "#{path}/$ref"
      ensure_local_ref!(ref, ref_path)
      ensure_no_cycle!(ref, stack, ref_path)

      target = lookup(ref, ref_path)
      resolve(target, path: path, stack: stack + [ref])
    end

    def ensure_local_ref!(ref, ref_path)
      return if ref.is_a?(String) && ref.start_with?('#/')

      raise_error(
        code: :remote_reference_unsupported,
        path: ref_path,
        hint: 'Replace the remote reference with a local component under #/components'
      )
    end

    def ensure_no_cycle!(ref, stack, ref_path)
      return if stack.size < MAX_REF_DEPTH && !stack.include?(ref)

      raise_error(code: :circular_reference, path: ref_path, hint: 'Break the reference cycle between local components')
    end

    def lookup(ref, path)
      segments = ref.sub(%r{\A#/}, '').split('/').map { |segment| unescape(segment) }
      segments.inject(@root) { |node, segment| descend(node, segment, ref, path) }
    end

    def descend(node, segment, ref, path)
      case node
      when Hash then descend_hash(node, segment, ref, path)
      when Array then descend_array(node, segment, ref, path)
      else raise_missing_reference(ref, path)
      end
    end

    def descend_hash(node, segment, ref, path)
      raise_missing_reference(ref, path) unless node.key?(segment)

      node.fetch(segment)
    end

    def descend_array(node, segment, ref, path)
      index = Integer(segment, exception: false)
      raise_missing_reference(ref, path) if index.nil? || index.negative? || index >= node.size

      node.fetch(index)
    end

    def raise_missing_reference(ref, path)
      raise_error(code: :missing_reference, path: path, hint: "Pointer #{ref} does not resolve to a component")
    end

    def escape(key)
      key.to_s.gsub('~', '~0').gsub('/', '~1')
    end

    def unescape(segment)
      segment.gsub('~1', '/').gsub('~0', '~')
    end

    def raise_error(code:, path:, hint:)
      raise SpecError, Generator::Diagnostic.new(
        severity: :error,
        code: code,
        message: "#{@source_name}: #{code} at #{path}",
        source_path: path,
        hint: hint
      )
    end
  end
end
