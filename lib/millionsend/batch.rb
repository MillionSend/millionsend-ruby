# frozen_string_literal: true

module Millionsend
  # Send up to 100 emails in a single call.
  module Batch
    class << self
      # POST /emails/batch with a bare array body. Supports idempotency_key:.
      def send(list, idempotency_key: nil)
        Millionsend::Request.new(
          method: :post, path: "/emails/batch", body: list, idempotency_key: idempotency_key
        ).perform
      end
      alias_method :create, :send
    end
  end
end
