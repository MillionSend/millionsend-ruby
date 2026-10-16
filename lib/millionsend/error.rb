# frozen_string_literal: true

module Millionsend
  # Base class for everything this SDK raises. Mirrors the API's wire error body
  # { statusCode, name, message }; #status_code is nil for client-side and
  # transport failures that never reached the API. #retry_after is the
  # response's retry-after header in seconds, nil when it sent none.
  class Error < StandardError
    attr_reader :status_code, :name, :retry_after

    def initialize(message, status_code = nil, name = nil, retry_after = nil)
      super(message)
      @status_code = status_code
      @name = name
      @retry_after = retry_after
    end

    # Build the right subclass from a non-2xx response, keyed on the stable
    # `name` discriminant. Falls back to ApplicationError for unknown names or a
    # body that is not the canonical error shape.
    def self.from_response(status, body, retry_after = nil)
      if body.is_a?(Hash)
        name = body[:name].is_a?(String) ? body[:name] : "application_error"
        message = body[:message].is_a?(String) ? body[:message] : "Request failed with status #{status}"
        code = body[:statusCode].is_a?(Integer) ? body[:statusCode] : status
      else
        name = "application_error"
        message = "Request failed with status #{status}"
        code = status
      end
      (ERROR_TYPES[name] || ApplicationError).new(message, code, name, retry_after)
    end
  end

  class ValidationError < Error; end
  class AllRecipientsSuppressedError < Error; end
  class NotFoundError < Error; end
  class MissingApiKeyError < Error; end
  class InvalidApiKeyError < Error; end
  class RestrictedApiKeyError < Error; end
  class ForbiddenError < Error; end
  class SendingPausedError < Error; end
  class BroadcastsPausedError < Error; end
  class RateLimitExceededError < Error; end
  class DailyQuotaExceededError < Error; end
  class InvalidIdempotentRequestError < Error; end
  class ConcurrentIdempotentRequestsError < Error; end
  class InboxSendPolicyError < Error; end
  class InboxSendCapReachedError < Error; end
  class ApprovalRequiredError < Error; end
  class EmailQuarantinedError < Error; end
  class EmailBlockedError < Error; end
  class TooManyWaitsError < Error; end
  class NameReviewUnavailableError < Error; end
  class InternalServerError < Error; end
  class ApplicationError < Error; end

  ERROR_TYPES = {
    "validation_error" => ValidationError,
    "all_recipients_suppressed" => AllRecipientsSuppressedError,
    "not_found" => NotFoundError,
    "missing_api_key" => MissingApiKeyError,
    "invalid_api_key" => InvalidApiKeyError,
    "restricted_api_key" => RestrictedApiKeyError,
    "forbidden" => ForbiddenError,
    "sending_paused" => SendingPausedError,
    "broadcasts_paused" => BroadcastsPausedError,
    "rate_limit_exceeded" => RateLimitExceededError,
    "daily_quota_exceeded" => DailyQuotaExceededError,
    "invalid_idempotent_request" => InvalidIdempotentRequestError,
    "concurrent_idempotent_requests" => ConcurrentIdempotentRequestsError,
    "inbox_send_policy" => InboxSendPolicyError,
    "inbox_send_cap_reached" => InboxSendCapReachedError,
    "approval_required" => ApprovalRequiredError,
    "email_quarantined" => EmailQuarantinedError,
    "email_blocked" => EmailBlockedError,
    "too_many_waits" => TooManyWaitsError,
    "name_review_unavailable" => NameReviewUnavailableError,
    "internal_server_error" => InternalServerError,
    "application_error" => ApplicationError,
  }.freeze
end
