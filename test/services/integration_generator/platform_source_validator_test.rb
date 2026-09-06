# frozen_string_literal: true

require 'test_helper'
require_relative '../../contracts/support/integration_generator_contract_helpers'

class PlatformSourceValidatorTest < Minitest::Test
  include GeneratorContractHelpers

  def setup
    @validator = Generator::PlatformSourceValidator.new
  end

  test 'accepts an optional field with a well-formed platform_source of each kind' do
    %i[constant attribute requisite_container unknown].each do |kind|
      field = base_field.with(required: false, platform_source: sample_platform_source(kind))

      assert_nil call(field, fields_by_name(field))
    end
  end

  test 'rejects a platform_source that is not a Hash with a known kind' do
    field = base_field.with(platform_source: { kind: :guessed })

    assert_equal :invalid_platform_source, call(field, fields_by_name(field))
  end

  test 'rejects an :attribute platform_source reading anything but operation.id or operation.amount' do
    field = base_field.with(platform_source: { kind: :attribute, attribute: 'external_id' })

    assert_equal :invalid_platform_source, call(field, fields_by_name(field))
  end

  test 'rejects a :constant platform_source whose value is not a safe scalar, before it can be rendered as executable Ruby' do
    malicious = Object.new
    malicious.define_singleton_method(:inspect) { 'system("id")' }
    field = base_field.with(platform_source: { kind: :constant, value: malicious })

    assert_equal :invalid_platform_source, call(field, fields_by_name(field))
  end

  test 'rejects a required field with an unresolved (:unknown) platform_source instead of shipping an incomplete payload' do
    field = base_field.with(required: true, platform_source: { kind: :unknown })

    assert_equal :invalid_platform_source, call(field, fields_by_name(field))
  end

  test 'accepts an optional field with an unresolved (:unknown) platform_source' do
    field = base_field.with(required: false, platform_source: { kind: :unknown })

    assert_nil call(field, fields_by_name(field))
  end

  test 'rejects a :requisite_container whose key lists are not safe String arrays' do
    malicious = Object.new
    malicious.define_singleton_method(:inspect) { 'system("id")' }
    field = base_field.with(
      platform_source: { kind: :requisite_container, requisite_type: 'sbp', known_keys: [malicious], unknown_keys: [] }
    )

    assert_equal :invalid_platform_source, call(field, fields_by_name(field))
  end

  test 'rejects a :requisite_container whose known_keys and unknown_keys overlap' do
    field = base_field.with(
      platform_source: { kind: :requisite_container, requisite_type: 'sbp', known_keys: %w[phone], unknown_keys: %w[phone] }
    )

    assert_equal :invalid_platform_source, call(field, fields_by_name(field))
  end

  test 'rejects required_if on a field whose own platform_source is not :attribute' do
    type_field = base_field.with(source_name: 'type', required: false, platform_source: { kind: :attribute, attribute: 'id' })
    field = base_field.with(
      source_name: 'recipient', required: false,
      platform_source: { kind: :requisite_container, requisite_type: 'sbp', known_keys: [], unknown_keys: [] },
      required_if: { field: 'recipient', condition: { field: 'type', equals: 'sbp' } }
    )

    assert_equal :invalid_required_if, call(field, fields_by_name(field, type_field))
  end

  test 'rejects required_if combined with required: true on the same field' do
    field = base_field.with(
      required: true, platform_source: { kind: :attribute, attribute: 'amount' },
      required_if: { field: 'amount', condition: { field: 'amount', equals: 'x' } }
    )

    assert_equal :invalid_required_if, call(field, fields_by_name(field))
  end

  test 'rejects a required_if rule whose condition field is not a sibling :attribute field' do
    non_attribute_sibling = base_field.with(source_name: 'type', required: false, platform_source: { kind: :constant, value: 'sbp' })
    field = base_field.with(
      required: false, platform_source: { kind: :attribute, attribute: 'amount' },
      required_if: { field: 'amount', condition: { field: 'type', equals: 'sbp' } }
    )

    assert_equal :invalid_required_if, call(field, fields_by_name(field, non_attribute_sibling))
  end

  test 'rejects a required_if condition.equals that is not a safe scalar, before it can be rendered as executable Ruby' do
    malicious = Object.new
    malicious.define_singleton_method(:inspect) { 'system("id")' }
    type_field = base_field.with(source_name: 'type', required: false, platform_source: { kind: :attribute, attribute: 'id' })
    field = base_field.with(
      required: false, platform_source: { kind: :attribute, attribute: 'amount' },
      required_if: { field: 'amount', condition: { field: 'type', equals: malicious } }
    )

    assert_equal :invalid_required_if, call(field, fields_by_name(field, type_field))
  end

  test 'accepts a required_if rule that references a sibling :attribute field with a safe scalar condition' do
    type_field = base_field.with(source_name: 'type', required: false, platform_source: { kind: :attribute, attribute: 'id' })
    field = base_field.with(
      required: false, platform_source: { kind: :attribute, attribute: 'amount' },
      required_if: { field: 'amount', condition: { field: 'type', equals: 'sbp' } }
    )

    assert_nil call(field, fields_by_name(field, type_field))
  end

  private

  def call(field, fields_by_name)
    code = nil
    @validator.call(field, fields_by_name) { |failed_code, _message| code = failed_code }
    code
  end

  def base_field = operation_ir.request_fields.first

  def fields_by_name(*fields)
    fields.to_h { |field| [field.source_name, field] }
  end

  def sample_platform_source(kind)
    case kind
    when :constant then { kind: :constant, value: 'RUB' }
    when :attribute then { kind: :attribute, attribute: 'amount' }
    when :requisite_container then { kind: :requisite_container, requisite_type: 'sbp', known_keys: ['phone'], unknown_keys: [] }
    else { kind: :unknown }
    end
  end
end
