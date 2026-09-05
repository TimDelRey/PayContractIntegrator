module Generator
  class Runner
    def initialize(
      builder: FileBuilder.new,
      verifier: FileVerifier.new,
      writer: ResultWriter.new,
      stdout: $stdout,
      stderr: $stderr
    )
      @builder = builder
      @verifier = verifier
      @writer = writer
      @stdout = stdout
      @stderr = stderr
    end

    def call(input)
      result = @builder.call(ir: input.ir)
      @verifier.call(result:)
      paths = @writer.call(
        result:,
        output: input.output,
        force: input.force
      )
      paths.each { |path| @stdout.puts(path) }
      0
    rescue PublicationError => e
      report(e.diagnostic)
      5
    rescue GenerationError => e
      report(e.diagnostic)
      4
    end

    private

    def report(error)
      location = " at #{error.source_path}" if error.source_path
      hint = " Hint: #{error.hint}" if error.hint
      @stderr.puts("#{error.severity}: #{error.code}: #{error.message}#{location}#{hint}")
    end
  end
end
