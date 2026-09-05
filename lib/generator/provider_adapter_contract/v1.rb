module Generator
  module ProviderAdapterContract
    module V1
      VERSION = '1'.freeze
      Result = Data.define(:success?, :data, :errors) do
        def failed? = !success?
      end

      class BaseService
        attr_reader :client

        def initialize(client: nil)
          @client = client
        end

        def check_conditions(_operation, _request_method)
          success
        end

        def create_request(_operation, _request_method = 'create')
          raise NotImplementedError
        end

        def fetch_status(_operation)
          raise NotImplementedError
        end

        def process_callback(raw_body:, headers:, payload:)
          raise NotImplementedError
        end

        private

        def success(data = nil)
          Result.new(success?: true, data:, errors: [].freeze)
        end

        def failure(code, message = nil)
          Result.new(success?: false, data: nil, errors: [code, message].compact.freeze)
        end
      end
    end
  end
end
