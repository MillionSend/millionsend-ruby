# frozen_string_literal: true

module Millionsend
  # Sending domains and their DNS records. Rows carry shared: (absent before
  # server v0.14.0, so nil reads as false). The team's subdomain of the shared
  # inbox domain is a read-only row with shared: true, sending_mode: ("open",
  # "reply_only" or "receive_only"), sending_mode_reason: ("plan", "instance"
  # or nil when open) and records: []; update, verify and remove raise
  # ForbiddenError on it. It only sends from an inbox's own address, so skip
  # it when picking a sender domain.
  module Domains
    class << self
      # POST /domains — name, region, custom_return_path, open_tracking,
      # click_tracking, tracking_subdomain. Returns the records to publish.
      def create(params)
        Millionsend::Request.new(method: :post, path: "/domains", body: params).perform
      end

      # GET /domains/:id — includes records[] with per-record status.
      def get(id)
        Millionsend::Request.new(method: :get, path: member_path(id)).perform
      end

      # GET /domains — accepts limit:/after:/before:. The shared row comes
      # last, after all of the team's own domains.
      def list(options = {})
        Millionsend::Request.new(method: :get, path: "/domains", query: Millionsend::Util.list_query(options)).perform
      end

      # PATCH /domains/:id — open_tracking, click_tracking, tracking_subdomain
      # (nil or "" clears it), receiving_catch_all (mail to addresses without
      # an inbox is kept rather than refused; paid plans on Cloud).
      def update(id, params)
        Millionsend::Request.new(method: :patch, path: member_path(id), body: params).perform
      end

      # POST /domains/:id/verify — re-check DNS now.
      def verify(id)
        Millionsend::Request.new(method: :post, path: "#{member_path(id)}/verify").perform
      end

      # DELETE /domains/:id
      def remove(id)
        Millionsend::Request.new(method: :delete, path: member_path(id)).perform
      end

      private

      def member_path(id)
        "/domains/#{Millionsend::Util.encode(id)}"
      end
    end
  end
end
