require 'digest'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'

module Generator
  class FileVerifier
    def call(result:)
      check_files(result)
      validate_provider_service(result)
      verify_examples_contract!(JSON.parse(result.examples))
    rescue KeyError => e
      fail_verification(:invalid_manifest, "Manifest is missing #{e.key.inspect}")
    rescue SyntaxError => e
      fail_verification(:invalid_generated_ruby, e.message)
    rescue JSON::ParserError => e
      fail_verification(:invalid_generated_json, e.message)
    end

    private

    def check_files(result)
      unless result.manifest.fetch('contract_version') == RESULT_CONTRACT_VERSION
        fail_verification(:unsupported_result_contract, 'Unsupported result contract version')
      end
      checksums = result.manifest.fetch('checksums')
      reject_unsafe_paths!([result.service_path])
      service_path = File.basename(result.service_path)
      expected_paths = [GUIDE_PATH, EXAMPLES_PATH, service_path].sort
      reject_unsafe_paths!(checksums.keys)
      fail_verification(:invalid_result, 'Result must contain exactly three files') unless checksums.keys.sort == expected_paths
      contents(result, service_path).each do |path, content|
        verify_checksum!(path, content, checksums.fetch(path))
      end
    end

    def validate_provider_service(result)
      RubyVM::InstructionSequence.compile(result.service)
      verify_service_contract!(result)
      verify_rubocop!(result.service)
    end

    def verify_service_contract!(result)
      provider_class = result.provider_class
      service = result.service
      unless service.match?(/class #{Regexp.escape(provider_class)} < BaseService/)
        fail_verification(:adapter_contract_mismatch, 'Generated service must inherit from BaseService')
      end
      result.operation_roles.each do |role|
        fail_verification(:unsupported_operation_role, "Unsupported operation role #{role.inspect}") unless OPERATION_ROLE_NAMES.include?(role)
        fail_verification(:adapter_contract_mismatch, "Missing generated method #{role}") unless service.match?(/def #{role}\b/)
      end
    end

    def verify_rubocop!(service)
      Dir.mktmpdir('integration-generator-verifier-') do |directory|
        path = File.join(directory, 'provider_service.rb')
        File.binwrite(path, service)
        command = [RbConfig.ruby, Gem.bin_path('rubocop', 'rubocop'), '--only', 'Lint', '--format', 'quiet', path]
        stdout, stderr, status = Open3.capture3(*command)
        fail_verification(:invalid_generated_rubocop, [stdout, stderr].join.strip) unless status.success?
      end
    end

    def verify_examples_contract!(examples)
      valid = examples.is_a?(Hash) && examples['contract_version'] == EXAMPLES_CONTRACT_VERSION &&
              examples['provider'].is_a?(String) && examples['operations'].is_a?(Array) &&
              examples['callbacks'].is_a?(Array)
      fail_verification(:invalid_examples_contract, "examples.json does not match contract version #{EXAMPLES_CONTRACT_VERSION}") unless valid
    end

    def contents(result, service_path)
      {
        service_path => result.service,
        GUIDE_PATH => result.guide,
        EXAMPLES_PATH => result.examples
      }
    end

    def reject_unsafe_paths!(paths)
      unsafe = paths.find do |path|
        path.start_with?('/') || path.split('/').include?('..') || path.include?('\\') || path.match?(/\A[A-Za-z]:/)
      end
      fail_verification(:unsafe_file_path, "Unsafe file path: #{unsafe.inspect}") if unsafe
    end

    def verify_checksum!(path, content, expected)
      actual = Digest::SHA256.hexdigest(content)
      fail_verification(:checksum_mismatch, "Checksum mismatch for #{path}") unless actual == expected
    end

    def fail_verification(code, message)
      raise GenerationError, Diagnostic.new(
        severity: :error, code:, message:, source_path: nil,
        hint: 'Generation stopped before publication'
      )
    end
  end
end
