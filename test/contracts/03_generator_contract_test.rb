require "test_helper"
require "json"
require_relative "support/integration_generator_contract_helpers"

class GeneratorContractTest < ActiveSupport::TestCase
  include IntegrationGeneratorContractHelpers

  test "generator creates the complete deterministic artifact set from IR" do
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
    assert_equal %w[INTEGRATION.md fixtures.json novapay_service.rb], first.manifest.keys.sort
  end

  test "generated service contains no literal credentials or real fixture data" do
    artifact_set = IntegrationGenerator::Generator.new(
      templates: IntegrationGenerator::TemplateRegistry.default
    ).call(ir: integration_ir)

    refute_match(/secret|password|Bearer\s+\S+/i, artifact_set.service)
    assert_match "ENV", artifact_set.service
    assert_match "example.test", artifact_set.fixtures
  end
end
