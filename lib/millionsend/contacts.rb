# frozen_string_literal: true

module Millionsend
  # Contacts live inside an audience or at the top level, and are addressable by
  # id or by email (email wins when an update hash carries both).
  module Contacts
    class << self
      # POST /audiences/:audience_id/contacts (or /contacts). audience_id is
      # addressing, not a body field, so it is stripped from the payload.
      def create(params)
        body = params.reject { |k, _| k == :audience_id }
        Millionsend::Request.new(method: :post, path: collection_path(params[:audience_id]), body: body).perform
      end

      # GET a single contact by id or email.
      def get(id_or_email, audience_id: nil)
        Millionsend::Request.new(method: :get, path: member_path(id_or_email, audience_id)).perform
      end

      # PATCH a contact. Addressing keys (:audience_id, :id, :email) are pulled
      # out; everything else is the body. A nil value clears a field; omit a key
      # to leave it unchanged.
      def update(params)
        key = params[:email] || params[:id]
        body = params.reject { |k, _| [:audience_id, :id, :email].include?(k) }
        Millionsend::Request.new(method: :patch, path: member_path(key, params[:audience_id]), body: body).perform
      end

      # DELETE a contact by id or email.
      def remove(id_or_email, audience_id: nil)
        Millionsend::Request.new(method: :delete, path: member_path(id_or_email, audience_id)).perform
      end

      # GET a list of contacts; pass audience_id: to scope it, plus limit:/after:/before:.
      def list(options = {})
        Millionsend::Request.new(
          method: :get, path: collection_path(options[:audience_id]), query: Millionsend::Util.list_query(options)
        ).perform
      end

      # PATCH /contacts/:id_or_email/topics with a bare array of
      # { id:, subscription: }. Mirrors resend-ruby's contacts.topics.update.
      def topics_update(id_or_email, topics)
        path = "/contacts/#{Millionsend::Util.encode(id_or_email)}/topics"
        Millionsend::Request.new(method: :patch, path: path, body: topics).perform
      end

      private

      def collection_path(audience_id)
        audience_id ? "/audiences/#{Millionsend::Util.encode(audience_id)}/contacts" : "/contacts"
      end

      def member_path(id_or_email, audience_id)
        key = Millionsend::Util.encode(id_or_email)
        audience_id ? "/audiences/#{Millionsend::Util.encode(audience_id)}/contacts/#{key}" : "/contacts/#{key}"
      end
    end
  end
end
