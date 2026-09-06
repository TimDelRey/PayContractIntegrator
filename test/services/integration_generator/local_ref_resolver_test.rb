# frozen_string_literal: true

require 'test_helper'

class IntegrationGeneratorLocalRefResolverTest < Minitest::Test
  test 'dereferences local component references in place' do
    document = {
      'paths' => {
        '/payouts' => {
          'post' => {
            'requestBody' => {
              'content' => {
                'application/json' => {
                  'schema' => { '$ref' => '#/components/schemas/Payout' }
                }
              }
            }
          }
        }
      },
      'components' => {
        'schemas' => {
          'Payout' => { 'type' => 'object', 'properties' => { 'amount' => { 'type' => 'integer' } } }
        }
      }
    }

    resolved = resolver.call(document:, source_name: 'spec.yaml')

    schema = resolved.dig('paths', '/payouts', 'post', 'requestBody', 'content', 'application/json', 'schema')
    assert_equal({ 'type' => 'object', 'properties' => { 'amount' => { 'type' => 'integer' } } }, schema)
    refute schema.equal?(document.dig('components', 'schemas', 'Payout'))
  end

  test 'dereferences the same component independently at multiple usage sites' do
    document = {
      'a' => { '$ref' => '#/components/schemas/Shared' },
      'b' => { '$ref' => '#/components/schemas/Shared' },
      'components' => { 'schemas' => { 'Shared' => { 'type' => 'string' } } }
    }

    resolved = resolver.call(document:, source_name: 'spec.yaml')

    assert_equal({ 'type' => 'string' }, resolved.fetch('a'))
    assert_equal({ 'type' => 'string' }, resolved.fetch('b'))
  end

  test 'rejects remote references with a structured diagnostic' do
    document = { 'schema' => { '$ref' => 'https://example.test/schemas.yaml#/Payout' } }

    error = assert_raises(IntegrationGenerator::SpecError) do
      resolver.call(document:, source_name: 'spec.yaml')
    end

    assert_equal :error, error.diagnostic.severity
    assert_equal :remote_reference_unsupported, error.diagnostic.code
    refute_nil error.diagnostic.source_path
    refute_nil error.diagnostic.hint
  end

  test 'rejects unresolvable pointers with a structured diagnostic' do
    document = { 'schema' => { '$ref' => '#/components/schemas/Missing' }, 'components' => { 'schemas' => {} } }

    error = assert_raises(IntegrationGenerator::SpecError) do
      resolver.call(document:, source_name: 'spec.yaml')
    end

    assert_equal :missing_reference, error.diagnostic.code
  end

  test 'rejects circular references instead of recursing forever' do
    document = {
      'components' => {
        'schemas' => {
          'A' => { '$ref' => '#/components/schemas/B' },
          'B' => { '$ref' => '#/components/schemas/A' }
        }
      }
    }

    error = assert_raises(IntegrationGenerator::SpecError) do
      resolver.call(document:, source_name: 'spec.yaml')
    end

    assert_equal :circular_reference, error.diagnostic.code
  end

  private

  def resolver
    IntegrationGenerator::LocalRefResolver.new
  end
end
