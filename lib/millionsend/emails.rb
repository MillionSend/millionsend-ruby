# frozen_string_literal: true

module Millionsend
  # Transactional email: send one, look it up, cancel a scheduled one.
  module Emails
    class << self
      # POST /emails. Pass idempotency_key: to make a send safe to retry.
      def send(params, idempotency_key: nil)
        Millionsend::Request.new(
          method: :post, path: "/emails", body: params, idempotency_key: idempotency_key
        ).perform
      end
      alias_method :create, :send

      # GET /emails/:id
      def get(id)
        Millionsend::Request.new(method: :get, path: "/emails/#{Millionsend::Util.encode(id)}").perform
      end

      # POST /emails/:id/cancel — scheduled, unsent emails only.
      def cancel(id)
        Millionsend::Request.new(method: :post, path: "/emails/#{Millionsend::Util.encode(id)}/cancel").perform
      end
    end
  end
end
