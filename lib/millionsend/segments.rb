# frozen_string_literal: true

module Millionsend
  # Dynamic segments — a saved filter over an audience's contacts. A MillionSend
  # extension with no Resend equivalent; served under /segments2.
  module Segments
    class << self
      # POST /segments2
      def create(params)
        Millionsend::Request.new(method: :post, path: "/segments2", body: params).perform
      end

      # GET /segments2/:id — also returns a live contact_count.
      def get(id)
        Millionsend::Request.new(method: :get, path: "/segments2/#{Millionsend::Util.encode(id)}").perform
      end

      # GET /segments2 — accepts limit:/after:/before:.
      def list(options = {})
        Millionsend::Request.new(
          method: :get, path: "/segments2", query: Millionsend::Util.list_query(options)
        ).perform
      end

      # PATCH /segments2/:id
      def update(id, params)
        Millionsend::Request.new(method: :patch, path: "/segments2/#{Millionsend::Util.encode(id)}", body: params).perform
      end

      # DELETE /segments2/:id
      def remove(id)
        Millionsend::Request.new(method: :delete, path: "/segments2/#{Millionsend::Util.encode(id)}").perform
      end
    end
  end
end
