require "test_helper"
require "json"
require_relative "support/integration_generator_contract_helpers"

class GeneratorContractTest < ActiveSupport::TestCase
  include IntegrationGeneratorContractHelpers

  test "generator creates a complete deterministic artifact set from IR" do
    generator = IntegrationGenerator::Generator.new(
      templates: IntegrationGenerator::TemplateRegistry.default
    )

    first = generator.call(ir: integration_ir)
    second = generator.call(ir: integration_ir)

    assert_instance_of IntegrationGenerator::ArtifactSet, first
    assert_equal first, second
    assert_match "class NovapayService", first.service
    assert_match "def create_request", first.service
    assert_match "# NovaPay Integration", first.guide
    assert_kind_of Hash, JSON.parse(first.fixtures)

    assert_equal "1.0", first.manifest.fetch("schema_version")
    assert_equal "1.0", first.manifest.fetch("ir_schema_version")
    assert_equal "1.0", first.manifest.fetch("mapping_schema_version")
    assert_equal "1", first.manifest.fetch("adapter_contract_version")
    assert_equal "app/services/provider/novapay_service.rb", first.manifest.fetch("service_install_path")
    assert_equal %w[INTEGRATION.md fixtures.json novapay_service.rb], first.manifest.fetch("artifacts").keys.sort
    first.manifest.fetch("artifacts").each_value do |metadata|
      assert_match(/\A[0-9a-f]{64}\z/, metadata.fetch("sha256"))
      assert_predicate metadata.fetch("template_version"), :present?
    end
  end

  test "generated output references configuration without embedding credential values" do
    artifact_set = IntegrationGenerator::Generator.new(
      templates: IntegrationGenerator::TemplateRegistry.default
    ).call(ir: integration_ir)

    assert_match(/ENV|configuration/, artifact_set.service)
    assert_match(/API_KEY|api_key/, artifact_set.service)
    refute_match(/test-api-key-value|literal-callback-secret|Bearer\s+[A-Za-z0-9._~-]{16,}/, artifact_set.service)
    assert_match "example.test", artifact_set.fixtures
  end

  test "generator rejects unsupported IR without returning partial artifacts" do
    unsupported_ir = integration_ir.with(schema_version: "2.0")

    error = assert_raises(IntegrationGenerator::GenerationError) do
      IntegrationGenerator::Generator.new(
        templates: IntegrationGenerator::TemplateRegistry.default
      ).call(ir: unsupported_ir)
    end

    assert_equal :unsupported_ir_version, error.diagnostic.code
    assert_equal :error, error.diagnostic.severity
  end
end
