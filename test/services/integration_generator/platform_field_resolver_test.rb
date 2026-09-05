# frozen_string_literal: true

require 'test_helper'

class IntegrationGeneratorPlatformFieldResolverTest < Minitest::Test
  test 'a single-value enum is classified as a constant' do
    result = classify('currency', { 'type' => 'string', 'enum' => ['RUB'] })

    assert_equal({ kind: :constant, value: 'RUB' }, result)
  end

  test 'a money field is classified as the amount attribute' do
    result = classify('amount', { 'type' => 'integer' }, money: { transformation: :rub_to_kopeck, entry: {} })

    assert_equal({ kind: :attribute, attribute: 'amount' }, result)
  end

  test 'an id-alias field name is classified as the id attribute' do
    result = classify('external_id', { 'type' => 'string' })

    assert_equal({ kind: :attribute, attribute: 'id' }, result)
  end

  test 'an object with known requisite keys is classified as a requisite container' do
    schema = recipient_schema(%w[sbp card])

    result = classify('recipient', schema)

    assert_equal :requisite_container, result.fetch(:kind)
    assert_equal 'sbp', result.fetch(:requisite_type)
    assert_equal %w[phone bank_code bank_name card_number], result.fetch(:known_keys)
    assert_empty result.fetch(:unknown_keys)
  end

  test 'a requisite container with more than one possible type reports it instead of choosing silently' do
    diagnostics = []

    classify('recipient', recipient_schema(%w[sbp card]), diagnostics: diagnostics)

    diagnostic = diagnostics.find { |item| item.code == :ambiguous_requisite_type }
    refute_nil diagnostic
    assert_equal :warning, diagnostic.severity
  end

  test 'a requisite container with a single possible type reports nothing' do
    diagnostics = []

    classify('recipient', recipient_schema(['sbp']), diagnostics: diagnostics)

    assert_empty diagnostics
  end

  test 'an object property with no recognizable requisite keys is not treated as a container' do
    schema = { 'type' => 'object', 'properties' => { 'foo' => { 'type' => 'string' } } }

    result = classify('metadata', schema)

    assert_equal({ kind: :unknown }, result)
  end

  test 'a field matching nothing else is classified as unknown rather than guessed' do
    result = classify('purpose', { 'type' => 'string' })

    assert_equal({ kind: :unknown }, result)
  end

  private

  def resolver
    IntegrationGenerator::PlatformFieldResolver.new
  end

  def classify(name, schema, money: nil, diagnostics: [])
    resolver.classify(name, schema, money: money, diagnostics: diagnostics)
  end

  def recipient_schema(types)
    {
      'type' => 'object',
      'required' => %w[type phone],
      'properties' => {
        'type' => { 'type' => 'string', 'enum' => types },
        'phone' => { 'type' => 'string' },
        'bank_code' => { 'type' => 'string' },
        'bank_name' => { 'type' => 'string' },
        'card_number' => { 'type' => 'string' }
      }
    }
  end
end
