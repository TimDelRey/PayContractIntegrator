require 'fileutils'
require 'securerandom'
require 'tmpdir'

module Generator
  class ResultWriter
    def initialize(rename: File.method(:rename))
      @rename = rename
    end

    def call(result:, output:, force: false)
      output = File.expand_path(output)
      check_output(output)
      parent = File.dirname(output)
      FileUtils.mkdir_p(parent)
      staging = Dir.mktmpdir('.integration-generator-', parent)
      backup = File.join(parent, ".#{File.basename(output)}.backup-#{Process.pid}-#{SecureRandom.hex(8)}")

      begin
        write_files(staging, result)
        replace_output(staging, output, backup, force)
        output_paths(output, result)
      ensure
        FileUtils.rm_rf(staging)
        FileUtils.remove_entry(backup) if File.exist?(backup) && File.exist?(output)
      end
    rescue Errno::EEXIST
      fail!(:output_conflict, "Output already exists: #{output}")
    rescue SystemCallError => e
      fail!(:publication_failed, e.message)
    end

    private

    def check_output(path)
      fail!(:unsafe_output_path, 'Output must not be a filesystem root') if File.dirname(path) == path
    end

    def write_files(staging, result)
      relative_path = result.service_path
      destination = File.join(staging, relative_path)
      File.binwrite(destination, result.service)
      File.binwrite(File.join(staging, GUIDE_PATH), result.guide)
      File.binwrite(File.join(staging, EXAMPLES_PATH), result.examples)
    end

    def replace_output(staging, output, backup, force)
      raise Errno::EEXIST, output if File.exist?(output) && !force

      @rename.call(output, backup) if File.exist?(output)
      @rename.call(staging, output)
    rescue StandardError
      @rename.call(backup, output) if File.exist?(backup) && !File.exist?(output)
      raise
    end

    def output_paths(output, result)
      paths = [result.service_path, GUIDE_PATH, EXAMPLES_PATH]
      paths.map { |path| File.join(output, path) }
    end

    def fail!(code, message)
      diagnostic = Diagnostic.new(
        severity: :error, code:, message:, source_path: nil,
        hint: 'Choose another output path or use --force'
      )
      raise PublicationError, diagnostic
    end
  end
end
