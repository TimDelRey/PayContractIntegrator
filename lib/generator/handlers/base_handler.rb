require 'digest'

module Generator
  module Handlers
    class BaseHandler
      def call(ir:)
        content = render(ir)
        verify_content!(content)
        build_file(content, ir)
      end

      private

      def render(*) = raise NotImplementedError
      def file_type = raise NotImplementedError
      def relative_path(*) = raise NotImplementedError

      def join_lines(*lines) = lines.join("\n")

      def verify_content!(content)
        return if content.is_a?(String) && !content.empty?

        fail_generation(:empty_file,
                        'Renderer produced an empty file')
      end

      def build_file(content, ir)
        content.freeze
        GeneratedFile.new(
          type: file_type,
          relative_path: relative_path(ir),
          content:,
          checksum: Digest::SHA256.hexdigest(content)
        )
      end

      def fail_generation(code, message, source_path: nil, hint: nil)
        raise GenerationError,
              Diagnostic.new(severity: :error, code:, message:, source_path:, hint:)
      end
    end
  end
end
