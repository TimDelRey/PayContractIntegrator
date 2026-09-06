require 'stringio'

module Generator
  class Pipeline
    SUPPORTED_LANGUAGES = %w[ruby].freeze

    def initialize(compiler: IntegrationGenerator::Compiler.new, runner_class: Runner)
      @compiler = compiler
      @runner_class = runner_class
    end

    def call(spec:, provider:, lang:, mapping: nil, output: 'output', force: false)
      return [:unsupported, [unsupported_language_diagnostic(lang)]] unless SUPPORTED_LANGUAGES.include?(lang)

      compiled = compile(spec, mapping, provider)
      return [:unsupported, compiled.diagnostics] if compiled.ir.nil?

      generate(compiled.ir, output, force)
    end

    private

    def unsupported_language_diagnostic(lang)
      Diagnostic.new(
        severity: :error, code: :unsupported_target_language,
        message: "Unsupported --lang #{lang.inspect}; only #{SUPPORTED_LANGUAGES.join(', ')} is supported",
        source_path: nil, hint: "Pass --lang #{SUPPORTED_LANGUAGES.first}"
      )
    end

    def compile(spec, mapping, provider)
      @compiler.call(
        source: File.read(spec), source_name: spec, provider_key: provider,
        mapping_source: mapping && File.read(mapping), mapping_source_name: mapping
      )
    end

    def generate(ir, output, force)
      stdout = StringIO.new
      stderr = StringIO.new
      input = GenerationInput.new(ir:, output:, force:)
      status = @runner_class.new(stdout:, stderr:).call(input)

      report(status, stdout, stderr)
    end

    def report(status, stdout, stderr)
      case status
      when 0 then [:ok, stdout.string.each_line.map(&:chomp)]
      when 4 then [:generation_failed, [stderr.string.strip]]
      when 5 then [:publication_failed, [stderr.string.strip]]
      end
    end
  end
end
