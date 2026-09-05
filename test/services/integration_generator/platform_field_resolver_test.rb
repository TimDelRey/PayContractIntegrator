# frozen_string_literal: true

require 'test_helper'

class IntegrationGeneratorPlatformFieldResolverTest < Minitest::Test
  test 'a single-value enum is classified as a constant' do
    result = resolver.classify('currency', { 'type' => 'string', 'enum' => ['RUB'] }, money: nil)

    assert_equal({ kind: :constant, value: 'RUB' }, result)
  end

  test 'a money field is classified as the amount attribute' do
    result = resolver.classify('amount', { 'type' => 'integer' }, money: { transformation: :rub_to_kopeck, entry: {} })

    assert_equal({ kind: :attribute, attribute: 'amount' }, result)
  end

  test 'an id-alias field name is classified as the id attribute' do
    result = resolver.classify('external_id', { 'type' => 'string' }, money: nil)

    assert_equal({ kind: :attribute, attribute: 'id' }, result)
  end

  test 'an object with known requisite keys is classified as a requisite container' do
    schema = {
      'type' => 'object',
      'required' => %w[type phone],
      'properties' => {
        'type' => { 'type' => 'string', 'enum' => %w[sbp card] },
        'phone' => { 'type' => 'string' },
        'bank_code' => { 'type' => 'string' },
        'bank_name' => { 'type' => 'string' },
        'card_number' => { 'type' => 'string' }
      }
    }

    result = resolver.classify('recipient', schema, money: nil)

    assert_equal :requisite_container, result.fetch(:kind)
    assert_equal 'sbp', result.fetch(:requisite_type)
    assert_equal %w[phone bank_code bank_name card_number], result.fetch(:known_keys)
    assert_empty result.fetch(:unknown_keys)
  end

  test 'an object property with no recognizable requisite keys is not treated as a container' do
    schema = { 'type' => 'object', 'properties' => { 'foo' => { 'type' => 'string' } } }

    result = resolver.classify('metadata', schema, money: nil)

    assert_equal({ kind: :unknown }, result)
  end

  test 'a field matching nothing else is classified as unknown rather than guessed' do
    result = resolver.classify('purpose', { 'type' => 'string' }, money: nil)

    assert_equal({ kind: :unknown }, result)
  end

  private

  def resolver
    IntegrationGenerator::PlatformFieldResolver.new
  end
end
