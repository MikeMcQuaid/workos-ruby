# frozen_string_literal: true

module WorkOS
  # A Net::HTTP based API client for interacting with the WorkOS API
  module Client
    include Kernel

    def client
      Net::HTTP.new(WorkOS.config.api_hostname, 443).tap do |http_client|
        http_client.use_ssl = true
        http_client.open_timeout = WorkOS.config.timeout
        http_client.read_timeout = WorkOS.config.timeout
        http_client.write_timeout = WorkOS.config.timeout if RUBY_VERSION >= '2.6.0'
      end
    end

    def execute_request(request:)
      begin
        response = client.request(request)
      rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
        raise TimeoutError.new(
          message: 'API Timeout Error',
        )
      end

      http_status = response.code.to_i
      handle_error_response(response: response) if http_status >= 400

      response
    end

    def get_request(path:, auth: false, params: {}, access_token: nil)
      uri = URI(path)
      uri.query = URI.encode_www_form(params) if params

      request = Net::HTTP::Get.new(
        uri.to_s,
        'Content-Type' => 'application/json',
      )

      request['Authorization'] = "Bearer #{access_token || WorkOS.config.key!}" if auth
      request['User-Agent'] = user_agent
      request
    end

    def post_request(path:, auth: false, idempotency_key: nil, body: nil)
      request = Net::HTTP::Post.new(path, 'Content-Type' => 'application/json')
      request.body = body.to_json if body
      request['Authorization'] = "Bearer #{WorkOS.config.key!}" if auth
      request['Idempotency-Key'] = idempotency_key if idempotency_key
      request['User-Agent'] = user_agent
      request
    end

    def delete_request(path:, auth: false, params: {})
      uri = URI(path)
      uri.query = URI.encode_www_form(params) if params

      request = Net::HTTP::Delete.new(
        uri.to_s,
        'Content-Type' => 'application/json',
      )

      request['Authorization'] = "Bearer #{WorkOS.config.key!}" if auth
      request['User-Agent'] = user_agent
      request
    end

    def put_request(path:, auth: false, idempotency_key: nil, body: nil)
      request = Net::HTTP::Put.new(path, 'Content-Type' => 'application/json')
      request.body = body.to_json if body
      request['Authorization'] = "Bearer #{WorkOS.config.key!}" if auth
      request['Idempotency-Key'] = idempotency_key if idempotency_key
      request['User-Agent'] = user_agent
      request
    end

    def user_agent
      engine = defined?(::RUBY_ENGINE) ? ::RUBY_ENGINE : 'Ruby'

      [
        'WorkOS',
        "#{engine}/#{RUBY_VERSION}",
        RUBY_PLATFORM,
        "v#{WorkOS::VERSION}"
      ].join('; ')
    end

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def handle_error_response(response:)
      http_status = response.code.to_i

      # Some responses don't have bodies
      json = response.body.nil? ? JSON.parse(response.body, object_class: OpenStruct) : nil

      case http_status
      when 400
        raise InvalidRequestError.new(
          message: response.message,
          http_status: http_status,
          request_id: response['x-request-id'],
          error: json.error,
          error_description: json.error_description,
          data: json,
          code: json.code,
        )
      when 401
        raise AuthenticationError.new(
          message: response.message,
          http_status: http_status,
          request_id: response['x-request-id'],
        )
      when 404
        raise NotFoundError.new(
          message: json.message,
          code: json.code,
          http_status: http_status,
          request_id: response['x-request-id'],
        )
      when 422
        raise UnprocessableEntityError.new(
          message: response.message,
          http_status: http_status,
          request_id: response['x-request-id'],
          error: json.error,
          error_description: json.message,
          code: json.code,
        )
      when 429
        raise RateLimitExceededError.new(
          message: response.message,
          http_status: http_status,
          request_id: response['x-request-id'],
          retry_after: response['Retry-After'],
        )
      else
        raise APIError.new(
          message: response.message,
          http_status: http_status,
          request_id: response['x-request-id'],
          code: json.code,
          error: json.error,
          error_description: json.error_description,
          data: json,
        )
      end
    end
  end
end
