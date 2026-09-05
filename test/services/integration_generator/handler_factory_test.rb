# frozen_string_literal: true

require 'test_helper'

class HandlerFactoryTest < Minitest::Test
  def setup
    @factory = Generator::HandlerFactory.new
  end

  test 'builds only registered handlers' do
    assert_instance_of Generator::Handlers::RubyServiceHandler,
                       @factory.build(file_type: :service)
    assert_instance_of Generator::Handlers::GuideHandler,
                       @factory.build(file_type: :guide)
    assert_instance_of Generator::Handlers::ExamplesHandler,
                       @factory.build(file_type: :examples)
  end

  test 'rejects unknown values without fallback' do
    error = assert_raises(Generator::GenerationError) do
      @factory.build(file_type: :unknown)
    end

    assert_equal :unsupported_file_type, error.diagnostic.code
  end
end
