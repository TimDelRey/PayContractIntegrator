require 'optparse'

module Generator
  class CLI
    REQUIRED_FLAGS = %i[spec provider lang].freeze

    def initialize(stdout: $stdout, stderr: $stderr, pipeline: Pipeline.new)
      @stdout = stdout
      @stderr = stderr
      @pipeline = pipeline
    end

    def call(argv)
      options = default_options
      parser = build_parser(options)
      parser.parse!(argv.dup)

      return help(parser) if options[:help]

      missing = REQUIRED_FLAGS.find { |flag| options[flag].nil? }
      return invalid_input("Missing required option --#{missing}") if missing

      run(options)
    rescue OptionParser::ParseError => e
      invalid_input(e.message)
    end

    private

    def default_options = { output: 'output', force: false }

    def build_parser(options)
      OptionParser.new do |parser|
        parser.banner = 'Usage: bin/integrate --spec FILE --provider NAME --lang LANG [--mapping FILE] [options]'
        parser.on('--spec FILE', 'OpenAPI specification path') { |value| options[:spec] = value }
        parser.on('--mapping FILE', 'Optional mapping override path') { |value| options[:mapping] = value }
        parser.on('--provider NAME', 'Provider key') { |value| options[:provider] = value }
        parser.on('--lang LANG', 'Target language (ruby)') { |value| options[:lang] = value }
        parser.on('--output DIR', 'Output directory (default: output)') { |value| options[:output] = value }
        parser.on('--force', 'Overwrite an existing output directory') { options[:force] = true }
        parser.on('-h', '--help', 'Show this help') { options[:help] = true }
      end
    end

    def help(parser)
      @stdout.puts(parser)
      0
    end

    def run(options)
      status, payload = @pipeline.call(
        spec: options.fetch(:spec), mapping: options[:mapping],
        provider: options.fetch(:provider), lang: options.fetch(:lang),
        output: options.fetch(:output), force: options.fetch(:force)
      )
      handle(status, payload)
    rescue SystemCallError => e
      invalid_input(e.message)
    end

    def handle(status, payload)
      case status
      when :ok then ok(payload)
      when :unsupported then unsupported(payload)
      when :generation_failed then failed(payload, 4)
      when :publication_failed then failed(payload, 5)
      end
    end

    def ok(paths)
      paths.each { |path| @stdout.puts(path) }
      0
    end

    def unsupported(diagnostics)
      diagnostics.each { |diagnostic| @stderr.puts(format_diagnostic(diagnostic)) }
      3
    end

    def failed(reasons, code)
      reasons.each { |reason| @stderr.puts(reason) }
      code
    end

    def format_diagnostic(diagnostic)
      location = " at #{diagnostic.source_path}" if diagnostic.source_path
      hint = " Hint: #{diagnostic.hint}" if diagnostic.hint
      "#{diagnostic.severity}: #{diagnostic.code}: #{diagnostic.message}#{location}#{hint}"
    end

    def invalid_input(message)
      @stderr.puts(message)
      2
    end
  end
end
