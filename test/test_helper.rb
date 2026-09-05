# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/integration_generator'
require_relative '../lib/generator'

module Minitest
  class Test
    def self.test(name, &)
      define_method("test_#{name.gsub(/\s+/, '_')}", &)
    end
  end
end
