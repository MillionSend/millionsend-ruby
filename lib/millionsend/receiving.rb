# frozen_string_literal: true

module Millionsend
  module Emails
    # Received mail: Resend's emails.receiving surface plus MillionSend's
    # long-poll, server-side reply and forward, and erase. Inbox-scoped keys
    # never see mail held for screening or in quarantine.
    module Receiving
      class << self
        # GET /emails/receiving. Options go on the query as given: limit:,
        # after:, before:, plus wait: (long-poll up to 50 s; the answer then
        # also lists held: [{ id:, inbox_id:, reason:, quarantine_reason:,
        # created_at: }] for matches held since the cursor), since:,
        # inbox_id:, to:, from: (an
        # address, or a domain covering its subdomains), subject_contains:,
        # unread: (with inbox_id:), include_quarantined: and quarantined: (held
        # mail too, or only; full-access keys).
        def list(options = {})
          Millionsend::Request.new(
            method: :get, path: "/emails/receiving", query: Millionsend::Util.csv_query(options)
          ).perform
        end

        # GET /emails/receiving/:id — html_format: "data_uri" (default) or
        # "cid". Adds screening, the spam and virus verdicts, extracted_text
        # and, for verification mail, extracted: { code:, link: }.
        def get(id, options = {})
          Millionsend::Request.new(method: :get, path: member_path(id), query: { html_format: options[:html_format] }).perform
        end

        # POST /emails/receiving/:id/reply — text/html, subject, cc, bcc,
        # reply_all, requires_approval, from, inbox_id. Returns { kind: "sent",
        # data: { object:, id:, thread_id:, inbox_id: } }, or { kind: "draft",
        # data: <draft> } when the inbox's rules held it for approval (202).
        # The trailing hash takes idempotency_key, flat or under options:.
        def reply(id, params, options = {})
          Millionsend::Request.new(
            method: :post, path: "#{member_path(id)}/reply", body: params, **Millionsend::Util.request_options(options)
          ).perform_outcome
        end

        # POST /emails/receiving/:id/forward — to (required), cc, bcc, a
        # text/html note, subject, requires_approval, from, inbox_id and mode
        # ("inline", the default, or "attachment" for the original as an .eml).
        # Same result and options as reply.
        def forward(id, params, options = {})
          Millionsend::Request.new(
            method: :post, path: "#{member_path(id)}/forward", body: params, **Millionsend::Util.request_options(options)
          ).perform_outcome
        end

        # DELETE /emails/receiving/:id — erases the message now (full-access
        # keys that are not scoped to an inbox).
        def remove(id)
          Millionsend::Request.new(method: :delete, path: member_path(id)).perform
        end

        def member_path(id)
          "/emails/receiving/#{Millionsend::Util.encode(id)}"
        end
      end

      # Attachments of a received email, each with a signed download_url valid
      # for one hour.
      module Attachments
        class << self
          # GET /emails/receiving/:email_id/attachments — limit:/after:/before:.
          # Also takes resend-ruby's single hash: list(email_id:, limit:).
          def list(email_id, options = {})
            if email_id.is_a?(Hash)
              options = email_id.reject { |k, _| k == :email_id }
              email_id = email_id[:email_id]
            end
            Millionsend::Request.new(
              method: :get, path: "#{Receiving.member_path(email_id)}/attachments",
              query: Millionsend::Util.list_query(options)
            ).perform
          end

          # GET /emails/receiving/:email_id/attachments/:id. Also takes
          # resend-ruby's get(email_id:, id:).
          def get(email_id, id = nil)
            email_id, id = email_id.values_at(:email_id, :id) if email_id.is_a?(Hash)
            path = "#{Receiving.member_path(email_id)}/attachments/#{Millionsend::Util.encode(id)}"
            Millionsend::Request.new(method: :get, path: path).perform
          end
        end
      end
    end
  end
end
