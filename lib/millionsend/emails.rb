# frozen_string_literal: true

module Millionsend
  # Transactional email: send one, look it up, cancel a scheduled one.
  module Emails
    class << self
      # POST /emails. Accepts a params hash or bare keywords
      # (Emails.send(from: ..., to: ...)); a trailing options hash carries
      # idempotency_key. No keyword parameters are declared on purpose — Ruby 3
      # keyword separation would otherwise reject the bare-keyword call shape.
      def send(params = {}, options = {})
        Millionsend::Request.new(
          method: :post, path: "/emails", body: params, idempotency_key: options[:idempotency_key]
        ).perform
      end
      alias_method :create, :send

      # GET /emails/:id
      def get(id)
        Millionsend::Request.new(method: :get, path: "/emails/#{Millionsend::Util.encode(id)}").perform
      end

      # GET /emails/:id/insights — the pre-send best-practice report computed
      # when the email was sent. 404 when the email is unknown or has no
      # insights yet. Check ids and band/severity/status values are an open
      # set that grows across score versions; they arrive as plain strings.
      def get_insights(id)
        Millionsend::Request.new(method: :get, path: "/emails/#{Millionsend::Util.encode(id)}/insights").perform
      end

      # POST /emails/:id/cancel — scheduled, unsent emails only.
      def cancel(id)
        Millionsend::Request.new(method: :post, path: "/emails/#{Millionsend::Util.encode(id)}/cancel").perform
      end
    end
  end
end
