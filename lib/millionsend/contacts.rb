# frozen_string_literal: true

module Millionsend
  # Contacts are team-global and addressable by id or by email (email wins when
  # an update hash carries both).
  module Contacts
    class << self
      # POST /contacts
      def create(params)
        Millionsend::Request.new(method: :post, path: "/contacts", body: params).perform
      end

      # GET a single contact by id or email.
      def get(id_or_email)
        Millionsend::Request.new(method: :get, path: member_path(id_or_email)).perform
      end

      # PATCH a contact. Addressing keys (:id, :email) are pulled out;
      # everything else is the body. A nil value clears a field; omit a key to
      # leave it unchanged.
      def update(params)
        key = params[:email] || params[:id]
        body = params.reject { |k, _| [:id, :email].include?(k) }
        Millionsend::Request.new(method: :patch, path: member_path(key), body: body).perform
      end

      # DELETE a contact by id or email.
      def remove(id_or_email)
        Millionsend::Request.new(method: :delete, path: member_path(id_or_email)).perform
      end

      # GET /contacts — accepts limit:/after:/before:.
      def list(options = {})
        Millionsend::Request.new(
          method: :get, path: "/contacts", query: Millionsend::Util.list_query(options)
        ).perform
      end

      # PATCH /contacts/:id_or_email/topics with a bare array of
      # { id:, subscription: }. Mirrors resend-ruby's contacts.topics.update.
      def topics_update(id_or_email, topics)
        Millionsend::Request.new(method: :patch, path: "#{member_path(id_or_email)}/topics", body: topics).perform
      end

      private

      def member_path(id_or_email)
        "/contacts/#{Millionsend::Util.encode(id_or_email)}"
      end
    end
  end
end
