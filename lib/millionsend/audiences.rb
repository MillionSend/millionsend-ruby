# frozen_string_literal: true

module Millionsend
  # Audiences — named contact lists (Resend-compatible).
  module Audiences
    class << self
      # POST /audiences
      def create(params)
        Millionsend::Request.new(method: :post, path: "/audiences", body: { name: params[:name] }).perform
      end

      # GET /audiences/:id
      def get(id)
        Millionsend::Request.new(method: :get, path: "/audiences/#{Millionsend::Util.encode(id)}").perform
      end

      # GET /audiences — accepts limit:/after:/before:.
      def list(options = {})
        Millionsend::Request.new(
          method: :get, path: "/audiences", query: Millionsend::Util.list_query(options)
        ).perform
      end

      # DELETE /audiences/:id
      def remove(id)
        Millionsend::Request.new(method: :delete, path: "/audiences/#{Millionsend::Util.encode(id)}").perform
      end
    end
  end
end
