# frozen_string_literal: true

module Millionsend
  # Send up to 100 emails in a single call.
  module Batch
    class << self
      # POST /emails/batch with a bare array body. A trailing options hash
      # carries idempotency_key (no keyword params, matching Emails.send).
      def send(list, options = {})
        Millionsend::Request.new(
          method: :post, path: "/emails/batch", body: list, idempotency_key: options[:idempotency_key]
        ).perform
      end
      alias_method :create, :send
    end
  end
end
