# frozen_string_literal: true

module Millionsend
  # Base class for everything this SDK raises. Mirrors the API's wire error body
  # { statusCode, name, message }; #status_code is nil for client-side and
  # transport failures that never reached the API.
  class Error < StandardError
    attr_reader :status_code, :name

    def initialize(message, status_code = nil, name = nil)
      super(message)
      @status_code = status_code
      @name = name
    end

    # Build the right subclass from a non-2xx response, keyed on the stable
    # `name` discriminant. Falls back to ApplicationError for unknown names or a
    # body that is not the canonical error shape.
    def self.from_response(status, body)
      if body.is_a?(Hash)
        name = body[:name].is_a?(String) ? body[:name] : "application_error"
        message = body[:message].is_a?(String) ? body[:message] : "Request failed with status #{status}"
        code = body[:statusCode].is_a?(Integer) ? body[:statusCode] : status
      else
        name = "application_error"
        message = "Request failed with status #{status}"
        code = status
      end
      (ERROR_TYPES[name] || ApplicationError).new(message, code, name)
    end
  end

  class ValidationError < Error; end
  class NotFoundError < Error; end
  class RestrictedApiKeyError < Error; end
  class SendingPausedError < Error; end
  class InvalidIdempotentRequestError < Error; end
  class ApplicationError < Error; end

  ERROR_TYPES = {
    "validation_error" => ValidationError,
    "not_found" => NotFoundError,
    "restricted_api_key" => RestrictedApiKeyError,
    "sending_paused" => SendingPausedError,
    "invalid_idempotent_request" => InvalidIdempotentRequestError,
    "application_error" => ApplicationError,
  }.freeze
end
