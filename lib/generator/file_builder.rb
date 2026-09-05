module Generator
  class FileBuilder
    def initialize(factory: HandlerFactory.new)
      @factory = factory
    end

    def call(ir:)
      validate_contract!(ir)
      ServiceValidator.new.call(ir)
      validate_adapter_contract!(ir)
      files = FILE_TYPES.map do |type|
        @factory.build(file_type: type).call(ir:)
      end
      build_result(ir, files)
    end

    private

    def build_result(ir, files)
      files_by_type = files.to_h { |file| [file.type, file] }
      Result.new(
        service: files_by_type.fetch(:service).content,
        guide: files_by_type.fetch(:guide).content,
        examples: files_by_type.fetch(:examples).content,
        service_path: files_by_type.fetch(:service).relative_path,
        provider_class: ir.provider_class,
        operation_roles: ir.operations.map(&:role).map(&:to_s).sort.freeze,
        manifest: manifest(ir, files)
      )
    end

    def validate_contract!(ir)
      return if ir.is_a?(IntegrationIR) && ir.contract_version == IR_CONTRACT_VERSION

      version = ir.contract_version if ir.respond_to?(:contract_version)
      raise GenerationError, Diagnostic.new(
        severity: :error, code: :unsupported_ir_version,
        message: "Unsupported IntegrationIR contract version: #{version || 'missing'}",
        source_path: nil, hint: "Compile input using IR contract version #{IR_CONTRACT_VERSION}"
      )
    end

    def validate_adapter_contract!(ir)
      version = ir.source_metadata[:adapter_contract_version] if ir.source_metadata.is_a?(Hash)
      return if version == ProviderAdapterContract::V1::VERSION

      raise GenerationError, Diagnostic.new(
        severity: :error, code: :unsupported_adapter_contract,
        message: "Unsupported adapter contract version: #{version || 'missing'}",
        source_path: nil, hint: "Use adapter contract version #{ProviderAdapterContract::V1::VERSION}"
      )
    end

    def manifest(ir, files)
      {
        'contract_version' => RESULT_CONTRACT_VERSION,
        'ir_contract_version' => ir.contract_version,
        'mapping_schema_version' => ir.source_metadata.fetch(:mapping_schema_version),
        'adapter_contract_version' => ir.source_metadata.fetch(:adapter_contract_version),
        'checksums' => files.sort_by(&:relative_path).to_h { |file| [file.relative_path, file.checksum] }.freeze
      }.freeze
    end
  end
end
