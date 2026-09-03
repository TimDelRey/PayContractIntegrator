module Service
  extend ActiveSupport::Concern

  ResultHttpStruct = Struct.new(:success?, :data, :errors, keyword_init: true)

  included do
    def self.call(*, **)
      new(*, **).call
    end

    def self.success(data = nil)
      ResultHttpStruct.new(success?: true, data: data, errors: [])
    end

    def self.failure(errors)
      ResultHttpStruct.new(success?: false, data: nil, errors: Array(errors))
    end

    def success(data = nil)
      self.class.success(data)
    end

    def failure(errors)
      self.class.failure(errors)
    end
  end
end
