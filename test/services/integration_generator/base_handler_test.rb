# frozen_string_literal: true

require 'test_helper'
require_relative '../../contracts/support/integration_generator_contract_helpers'

class BaseHandlerTest < Minitest::Test
  include GeneratorContractHelpers

  class RecordingHandler < Generator::Handlers::BaseHandler
    attr_reader :calls

    def initialize(**)
      super
      @calls = []
    end

    private

    def render(_context)
      calls << :render
      'content'
    end

    def verify_content!(content)
      calls << :verify
      super
    end

    def file_type = :recording
    def relative_path(_ir) = 'recording.txt'
  end

  test 'owns the fixed template method sequence' do
    handler = RecordingHandler.new

    file = handler.call(ir: integration_ir)

    assert_equal %i[render verify], handler.calls
    assert_equal 'content', file.content
    assert_predicate file, :frozen?
  end

  test 'requires subclasses to implement rendering' do
    assert_raises(NotImplementedError) do
      Generator::Handlers::BaseHandler.new.call(ir: integration_ir)
    end
  end
end
