# frozen_string_literal: true

module Millionsend
  # Contacts are team-global and addressable by id or by email (email wins when
  # an update hash carries both).
  module Contacts
    class << self
      # POST /contacts — email, first_name, last_name, unsubscribed, properties,
      # segments: [{ id: }], topics: [{ id:, subscription: }].
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
        body = params.reject { |k, _| [:id, :email].include?(k) }
        Millionsend::Request.new(method: :patch, path: member_path(params), body: body).perform
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
      # { id:, subscription: }. Contacts::Topics.update is the resend-ruby shape.
      def topics_update(id_or_email, topics)
        Millionsend::Request.new(method: :patch, path: "#{member_path(id_or_email)}/topics", body: topics).perform
      end

      # Every member method also accepts resend-ruby's addressing hash
      # ({ id: } / { email: } / { contact_id: }) in place of the bare value.
      def member_path(id_or_email)
        id_or_email = id_or_email[:email] || id_or_email[:id] || id_or_email[:contact_id] if id_or_email.is_a?(Hash)
        "/contacts/#{Millionsend::Util.encode(id_or_email)}"
      end
    end

    # Topic subscriptions of one contact, in resend-ruby's nested shape.
    module Topics
      class << self
        # GET /contacts/:id_or_email/topics — { id: | email: } or a bare id/email.
        # Every topic comes back with the contact's effective subscription;
        # explicit: false means it is the topic's default, not a stored choice.
        # Unpaginated, like Topics.list.
        def list(params)
          Millionsend::Request.new(method: :get, path: "#{Millionsend::Contacts.member_path(params)}/topics").perform
        end

        # PATCH /contacts/:id_or_email/topics — { id: | email:, topics: [{ id:, subscription: }] }.
        def update(params)
          Millionsend::Contacts.topics_update(params, params[:topics])
        end
      end
    end

    # Bulk contact creation — a MillionSend extension (Resend imports via CSV).
    module Batch
      class << self
        # POST /contacts/batch with a bare array of up to 1000 create payloads.
        # Options (flat or under options:): on_conflict ("error" default,
        # "skip", "upsert") for emails that already belong to a contact,
        # batch_validation ("strict" default, "permissive" writes the valid
        # subset and lists failures under errors[]), idempotency_key. Returns
        # { data: [{ index:, id:, status: }], counts: {...}, errors: [...] }.
        def create(list, options = {})
          options = options[:options] if options.is_a?(Hash) && options.key?(:options)
          Millionsend::Request.new(
            method: :post, path: "/contacts/batch", body: list,
            query: { on_conflict: options[:on_conflict] },
            **Millionsend::Util.request_options(options)
          ).perform
        end
      end
    end

    # Segment membership of one contact. Segments are dynamic filters, so this
    # only applies to segments that hold an explicit member list.
    module Segments
      class << self
        # POST /contacts/:id_or_email/segments/:segment_id. Takes
        # (id_or_email, segment_id) or resend-ruby's { contact_id: | email:, segment_id: }.
        def add(id_or_email, segment_id = nil)
          Millionsend::Request.new(method: :post, path: path(id_or_email, segment_id)).perform
        end

        # DELETE /contacts/:id_or_email/segments/:segment_id — same shapes as add.
        def remove(id_or_email, segment_id = nil)
          Millionsend::Request.new(method: :delete, path: path(id_or_email, segment_id)).perform
        end

        private

        def path(id_or_email, segment_id)
          segment_id ||= id_or_email[:segment_id] if id_or_email.is_a?(Hash)
          "#{Millionsend::Contacts.member_path(id_or_email)}/segments/#{Millionsend::Util.encode(segment_id)}"
        end
      end
    end
  end
end
