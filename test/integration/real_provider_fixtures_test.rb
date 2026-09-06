# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'tmpdir'

class RealProviderFixturesTest < Minitest::Test
  FIXTURES_DIR = File.expand_path('../fixtures/integration_generator/providers', __dir__)

  test 'compiles the real SumUp specification, resolving checkout create/status operations' do
    result = compile_fixture('sumup')

    refute_nil result.ir
    ir = result.ir

    assert_equal 'SumupService', ir.provider_class
    assert_equal(
      { 'CreateCheckout' => :create_request, 'GetCheckout' => :fetch_status },
      ir.operations.to_h { |operation| [operation.id, operation.role] }
    )
    assert_equal [{ type: :bearer, location: :header, name: 'Authorization' }], ir.auth_schemes
  end

  test 'generates a complete service, guide, and fixtures for the real SumUp specification' do
    Dir.mktmpdir do |directory|
      output = File.join(directory, 'output')

      status, paths = Generator::Pipeline.new.call(
        spec: fixture_path('sumup'), mapping: File.join(FIXTURES_DIR, 'sumup_mapping.yml'),
        provider: 'sumup', lang: 'ruby', output:
      )

      assert_equal :ok, status
      service = File.read(paths.find { |path| path.end_with?('_service.rb') })
      guide = File.read(paths.find { |path| path.end_with?('INTEGRATION.md') })
      fixtures = File.read(paths.find { |path| path.end_with?('fixtures.json') })

      RubyVM::InstructionSequence.compile(service)
      assert_match 'operation.public_send("id")', service
      assert_match 'Integer(value) * 1', service
      assert_match 'payload["currency"] = "EUR"', service
      assert_match 'ENV.fetch("SUMUP_MERCHANT_CODE")', service

      assert_match 'SUMUP_MERCHANT_CODE', guide
      assert_match '`description` -- add an override', guide

      assert_kind_of Hash, JSON.parse(fixtures)
    end
  end

  test 'compiles the real Adyen payout specification, reporting genuine ambiguity between candidate operations instead of guessing' do
    result = compile_fixture('adyen')

    assert_nil result.ir
    codes = result.diagnostics.map(&:code)
    assert_includes codes, :ambiguous_payment_resource
    assert_includes codes, :no_operations_resolved
  end

  test 'generates a complete service for the real Adyen spec once mapping resolves the role and nested amount' do
    Dir.mktmpdir do |directory|
      output = File.join(directory, 'output')

      status, paths = Generator::Pipeline.new.call(
        spec: fixture_path('adyen'), mapping: File.join(FIXTURES_DIR, 'adyen_mapping.yml'),
        provider: 'adyen', lang: 'ruby', output:
      )

      assert_equal :ok, status
      service = File.read(paths.find { |path| path.end_with?('_service.rb') })
      guide = File.read(paths.find { |path| path.end_with?('INTEGRATION.md') })
      fixtures = File.read(paths.find { |path| path.end_with?('fixtures.json') })

      RubyVM::InstructionSequence.compile(service)
      assert_match 'payload["amount"] = { "value" => Integer(value) * 100, "currency" => "EUR" }', service
      assert_match 'operation.public_send("id")', service
      assert_match 'ENV.fetch("ADYEN_MERCHANT_ACCOUNT")', service

      assert_match 'ADYEN_MERCHANT_ACCOUNT', guide
      assert_match '`shopper_name` -- add an override', guide

      assert_kind_of Hash, JSON.parse(fixtures)
    end
  end

  test 'compiles the real PayPal specification converted from JSON to YAML, treating its OAuth2 scheme as a bearer token like any other' do
    result = compile_fixture('paypal')

    refute_nil result.ir
    ir = result.ir

    assert_equal 'PaypalService', ir.provider_class
    assert_equal(
      { 'payouts.post' => :create_request, 'payouts.get' => :fetch_status },
      ir.operations.to_h { |operation| [operation.id, operation.role] }
    )
    assert_equal [{ type: :bearer, location: :header, name: 'Authorization' }], ir.auth_schemes
  end

  test 'refuses to generate the real PayPal service because its batch request body has no flat, single-operation shape' do
    Dir.mktmpdir do |directory|
      status, payload = Generator::Pipeline.new.call(
        spec: fixture_path('paypal'), provider: 'paypal', lang: 'ruby', output: File.join(directory, 'output')
      )

      assert_equal :generation_failed, status
      assert_match 'invalid_platform_source', payload.first
    end
  end

  private

  def compile_fixture(name)
    IntegrationGenerator::Compiler.new.call(
      source: File.read(fixture_path(name)), source_name: "#{name}_provider_api.yaml", provider_key: name
    )
  end

  def fixture_path(name) = File.join(FIXTURES_DIR, "#{name}_provider_api.yaml")
end
