require 'test_helper'
require 'tmpdir'

class PipelineTest < Minitest::Test
  test 'rejects an unsupported target language before invoking the compiler' do
    compiler = flunking_collaborator
    pipeline = build_pipeline(compiler:)

    with_files do |spec, mapping|
      status, diagnostics = pipeline.call(spec:, mapping:, provider: 'novapay', lang: 'python')

      assert_equal :unsupported, status
      assert_equal :unsupported_target_language, diagnostics.first.code
    end
  end

  test 'surfaces Spec Compiler diagnostics as unsupported without generating' do
    diagnostic = Generator::Diagnostic.new(
      severity: :error, code: :no_operations_resolved, message: 'nothing to generate', source_path: '#/paths', hint: nil
    )
    compiler = stub_collaborator { Generator::CompileResult.new(ir: nil, diagnostics: [diagnostic]) }
    runner_class = flunking_runner_class
    pipeline = build_pipeline(compiler:, runner_class:)

    with_files do |spec, mapping|
      status, diagnostics = pipeline.call(spec:, mapping:, provider: 'novapay', lang: 'ruby')

      assert_equal :unsupported, status
      assert_equal [diagnostic], diagnostics
    end
  end

  test 'reports a successful run as the paths Runner printed to stdout' do
    ir = compiled_ir
    runner_class = stub_runner_class(exit_code: 0, stdout_lines: %w[output/novapay_service.rb output/INTEGRATION.md])
    pipeline = build_pipeline(ir:, runner_class:)

    with_files do |spec, mapping|
      status, payload = pipeline.call(spec:, mapping:, provider: 'novapay', lang: 'ruby')

      assert_equal :ok, status
      assert_equal %w[output/novapay_service.rb output/INTEGRATION.md], payload
    end
  end

  test 'maps a generation failure exit code to :generation_failed with the reported message' do
    runner_class = stub_runner_class(exit_code: 4, stderr_line: 'error: unsupported_ir_version: nope')
    pipeline = build_pipeline(ir: compiled_ir, runner_class:)

    with_files do |spec, mapping|
      status, reasons = pipeline.call(spec:, mapping:, provider: 'novapay', lang: 'ruby')

      assert_equal :generation_failed, status
      assert_equal ['error: unsupported_ir_version: nope'], reasons
    end
  end

  test 'maps a publication failure exit code to :publication_failed with the reported message' do
    runner_class = stub_runner_class(exit_code: 5, stderr_line: 'error: output_conflict: nope')
    pipeline = build_pipeline(ir: compiled_ir, runner_class:)

    with_files do |spec, mapping|
      status, reasons = pipeline.call(spec:, mapping:, provider: 'novapay', lang: 'ruby')

      assert_equal :publication_failed, status
      assert_equal ['error: output_conflict: nope'], reasons
    end
  end

  private

  def build_pipeline(ir: compiled_ir, compiler: nil, runner_class: stub_runner_class(exit_code: 0))
    compiler ||= stub_collaborator { Generator::CompileResult.new(ir:, diagnostics: []) }
    Generator::Pipeline.new(compiler:, runner_class:)
  end

  def compiled_ir = Object.new

  def with_files
    Dir.mktmpdir do |directory|
      spec = File.join(directory, 'spec.yaml')
      mapping = File.join(directory, 'mapping.yml')
      File.write(spec, 'openapi: 3.1.0')
      File.write(mapping, 'schema_version: "1.0"')
      yield spec, mapping
    end
  end

  def stub_collaborator(&block)
    Object.new.tap { |object| object.define_singleton_method(:call) { |**_arguments| block.call } }
  end

  def flunking_collaborator
    Object.new.tap { |object| object.define_singleton_method(:call) { |**_arguments| flunk 'must not be called' } }
  end

  def flunking_runner_class
    Class.new do
      define_method(:initialize) do |stdout:, stderr:|
        @stdout = stdout
        @stderr = stderr
      end
      define_method(:call) { |_input| flunk 'must not be called' }
    end
  end

  def stub_runner_class(exit_code:, stdout_lines: [], stderr_line: nil)
    Class.new do
      define_method(:initialize) do |stdout:, stderr:|
        @stdout = stdout
        @stderr = stderr
      end

      define_method(:call) do |_input|
        stdout_lines.each { |line| @stdout.puts(line) }
        @stderr.puts(stderr_line) if stderr_line
        exit_code
      end
    end
  end
end
