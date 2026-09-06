# frozen_string_literal: true

require 'test_helper'
require_relative '../../contracts/support/integration_generator_contract_helpers'

class FieldRendererTest < Minitest::Test
  include GeneratorContractHelpers

  def setup
    @renderer = Generator::Handlers::FieldRenderer.new
  end

  test 'renders an :attribute field via a memoized local, applying its money transformation' do
    field = base_field.with(source_name: 'amount', target_name: 'amount', platform_source: { kind: :attribute, attribute: 'amount' })

    expected = [
      '  value = operation.public_send("amount")',
      '  payload["amount"] = Integer(value) * 100'
    ].join("\n")

    assert_equal expected, @renderer.render(field, [field], integration_ir)
  end

  test 'renders an optional :attribute field guarded by respond_to? and non-nil, ignoring source_name' do
    field = base_field.with(
      source_name: 'external_id', target_name: 'external_id', required: false, transformation: nil,
      platform_source: { kind: :attribute, attribute: 'id' }
    )

    expected = [
      '  value = operation.public_send("id")',
      '  payload["external_id"] = value if operation.respond_to?("id") && !value.nil?'
    ].join("\n")

    assert_equal expected, @renderer.render(field, [field], integration_ir.with(money_transformations: []))
  end

  test 'renders a :constant field as a literal value, never reading the operation' do
    field = base_field.with(source_name: 'currency', target_name: 'currency', platform_source: { kind: :constant, value: 'RUB' })

    assert_equal '  payload["currency"] = "RUB"', @renderer.render(field, [field], integration_ir)
  end

  test 'renders a :configuration field from ENV using the provider env_prefix, never reading the operation' do
    field = base_field.with(
      source_name: 'merchant_code', target_name: 'merchant_code',
      platform_source: { kind: :configuration, name: 'MERCHANT_CODE' }
    )

    rendered = @renderer.render(field, [field], integration_ir.with(env_prefix: 'SUMUP'))

    assert_equal '  payload["merchant_code"] = ENV.fetch("SUMUP_MERCHANT_CODE")', rendered
  end

  test 'renders a :money_container field as a nested {value, currency} Hash, applying the money transformation to value only' do
    field = base_field.with(
      source_name: 'amount', target_name: 'amount',
      platform_source: { kind: :money_container, value_key: 'value', currency_key: 'currency', currency: 'EUR' }
    )

    expected = [
      '  value = operation.public_send("amount")',
      '  payload["amount"] = { "value" => Integer(value) * 100, "currency" => "EUR" }'
    ].join("\n")

    assert_equal expected, @renderer.render(field, [field], integration_ir)
  end

  test 'renders an :unknown field as a TODO comment, never guessing a read path' do
    field = base_field.with(source_name: 'mystery', target_name: 'mystery', platform_source: { kind: :unknown })

    rendered = @renderer.render(field, [field], integration_ir)

    assert_match(/\A  # TODO:/, rendered)
    assert_match "'mystery'", rendered
    refute_match 'operation.public_send', rendered
  end

  test 'renders a :requisite_container field as a nested Hash read via a memoized operation.payout_requisite local' do
    field = base_field.with(
      source_name: 'recipient', target_name: 'recipient',
      platform_source: { kind: :requisite_container, requisite_type: 'sbp', known_keys: %w[phone bank_code], unknown_keys: [] }
    )

    expected = [
      '  requisite = operation.payout_requisite',
      '  payload["recipient"] = {',
      '    "type" => "sbp",',
      '    "phone" => requisite&.dig("sbp", "phone"),',
      '    "bank_code" => requisite&.dig("sbp", "bank_code")',
      '  }'
    ].join("\n")

    assert_equal expected, @renderer.render(field, [field], integration_ir)
  end

  test 'a :requisite_container with no type-selector omits the "type" entry entirely instead of emitting "type" => nil' do
    field = base_field.with(
      source_name: 'recipient', target_name: 'recipient',
      platform_source: { kind: :requisite_container, requisite_type: nil, known_keys: ['phone'], unknown_keys: [] }
    )

    expected = [
      '  requisite = operation.payout_requisite',
      '  payload["recipient"] = {',
      '    "phone" => requisite&.dig("phone")',
      '  }'
    ].join("\n")

    assert_equal expected, @renderer.render(field, [field], integration_ir)
  end

  test 'a :requisite_container unknown_key becomes a TODO comment above the Hash, not a guessed read' do
    field = base_field.with(
      source_name: 'recipient', target_name: 'recipient',
      platform_source: { kind: :requisite_container, requisite_type: 'sbp', known_keys: ['phone'], unknown_keys: ['iban'] }
    )

    rendered = @renderer.render(field, [field], integration_ir)

    assert_match(/\A  # TODO:.*'recipient\.iban'/, rendered)
    refute_match 'iban" =>', rendered
  end

  test 'a required_if field fails clearly when its condition holds but the value is nil, otherwise omits it silently' do
    type_field = base_field.with(source_name: 'type', target_name: 'type', platform_source: { kind: :attribute, attribute: 'type' })
    field = base_field.with(
      source_name: 'bank_code', target_name: 'bank_code', required: false, transformation: nil,
      platform_source: { kind: :attribute, attribute: 'id' },
      required_if: { field: 'bank_code', condition: { field: 'type', equals: 'sbp' } }
    )

    expected = [
      '  value = operation.public_send("id")',
      '  if operation.public_send("type") == "sbp" && value.nil?',
      '    return failure(:missing_conditional_field, "bank_code is required when type is sbp")',
      '  end',
      '  payload["bank_code"] = value unless value.nil?'
    ].join("\n")

    assert_equal expected, @renderer.render(field, [field, type_field], integration_ir.with(money_transformations: []))
  end

  private

  def base_field = operation_ir.request_fields.first
end
