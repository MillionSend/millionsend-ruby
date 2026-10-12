# frozen_string_literal: true

module Millionsend
  # Agent and human inboxes (Resend's Inboxes beta plus MillionSend's
  # extensions): addresses whose mail lands in threads, with labels, drafts,
  # safety rules, quarantine and code extraction. Lists that take arrays
  # (folders:, labels:, from:...) send them comma-separated.
  module Inboxes
    class << self
      # POST /inboxes — every field optional: email_address (omitted, a random
      # address on the shared domain), name, from_name, forwarding, kind
      # ("agent", the default, or "human"), expires_in ("24h", "7d"...; nil
      # never expires) and safety (any subset of the rules). Returns the inbox.
      def create(params = {})
        Millionsend::Request.new(method: :post, path: "/inboxes", body: params).perform
      end

      # GET /inboxes — limit:/after:/before: and kind:. Newest first.
      def list(options = {})
        Millionsend::Request.new(method: :get, path: "/inboxes", query: Millionsend::Util.csv_query(options)).perform
      end

      # GET /inboxes/:id_or_email
      def get(id_or_email)
        Millionsend::Request.new(method: :get, path: member_path(id_or_email)).perform
      end

      # PATCH /inboxes/:id — name, from_name ("" removes it), expires_in (nil
      # never expires). Returns the inbox.
      def update(id, params)
        Millionsend::Request.new(method: :patch, path: member_path(id), body: params).perform
      end

      # DELETE /inboxes/:id — its threads, drafts and labels go with it, and
      # its inbox-scoped keys are revoked.
      def remove(id)
        Millionsend::Request.new(method: :delete, path: member_path(id)).perform
      end

      def member_path(id)
        "/inboxes/#{Millionsend::Util.encode(id)}"
      end
    end

    # Who may write in and what an agent may send (MillionSend extension).
    module Safety
      class << self
        # GET /inboxes/:id/safety
        def get(inbox_id)
          Millionsend::Request.new(method: :get, path: "#{Inboxes.member_path(inbox_id)}/safety").perform
        end

        # PATCH /inboxes/:id/safety — any subset of accept_from, allowlist,
        # owner_addresses, screening, extract_codes, send_policy,
        # require_approval, private_codes, send_cap (nil: no cap) and
        # forward_to. Returns every rule.
        def update(inbox_id, params)
          Millionsend::Request.new(method: :patch, path: "#{Inboxes.member_path(inbox_id)}/safety", body: params).perform
        end
      end
    end

    # Verification codes and sign-in links found in received mail
    # (MillionSend extension). Links are never fetched.
    module Codes
      class << self
        # GET /inboxes/:id/codes/latest — from: (an address, or a domain
        # covering its subdomains), wait: (0-50 s), max_age: (60-86400 s,
        # default 600). Always 200; status is "found", "none", "ambiguous" or
        # "timeout".
        def latest(inbox_id, options = {})
          Millionsend::Request.new(
            method: :get, path: "#{Inboxes.member_path(inbox_id)}/codes/latest",
            query: Millionsend::Util.csv_query(options)
          ).perform
        end
      end
    end

    # Mail the inbox's rules held back (MillionSend extension): kept and
    # listed, but never shown to agents until a person releases it.
    module Quarantine
      class << self
        # GET /inboxes/:id/quarantine — limit:/after:/before:. Newest first.
        def list(inbox_id, options = {})
          Millionsend::Request.new(
            method: :get, path: "#{Inboxes.member_path(inbox_id)}/quarantine",
            query: Millionsend::Util.list_query(options)
          ).perform
        end

        # POST /inboxes/:id/quarantine/:email_id/release — trust_sender: true
        # also adds the sender to the allowlist.
        def release(inbox_id, email_id, params = {})
          path = "#{Inboxes.member_path(inbox_id)}/quarantine/#{Millionsend::Util.encode(email_id)}/release"
          Millionsend::Request.new(method: :post, path: path, body: params).perform
        end
      end
    end

    # Labels of one inbox, applied to threads one at a time.
    module Labels
      class << self
        # GET /inboxes/:id/labels — every label, oldest first (unpaginated).
        def list(inbox_id)
          Millionsend::Request.new(method: :get, path: "#{Inboxes.member_path(inbox_id)}/labels").perform
        end

        # POST /inboxes/:id/labels — name, color ("#RRGGBB"; random when omitted).
        def create(inbox_id, params)
          Millionsend::Request.new(method: :post, path: "#{Inboxes.member_path(inbox_id)}/labels", body: params).perform
        end

        # PATCH /inboxes/:id/labels/:label_id — name and/or color.
        def update(inbox_id, label_id, params)
          Millionsend::Request.new(method: :patch, path: member_path(inbox_id, label_id), body: params).perform
        end

        # DELETE /inboxes/:id/labels/:label_id — also takes it off every thread.
        def remove(inbox_id, label_id)
          Millionsend::Request.new(method: :delete, path: member_path(inbox_id, label_id)).perform
        end

        private

        def member_path(inbox_id, label_id)
          "#{Inboxes.member_path(inbox_id)}/labels/#{Millionsend::Util.encode(label_id)}"
        end
      end
    end

    # Conversations of one inbox, in both directions.
    module Threads
      class << self
        # GET /inboxes/:id/threads — folders: (["inbox"] by default), labels:,
        # read:, include_quarantined:, limit:/after:/before:. Most recently
        # active first.
        def list(inbox_id, options = {})
          Millionsend::Request.new(
            method: :get, path: "#{Inboxes.member_path(inbox_id)}/threads", query: Millionsend::Util.csv_query(options)
          ).perform
        end

        # GET /inboxes/:id/threads/search — list's options plus query:, from:,
        # to:, cc:, bcc:, has_attachment:, start_date:, end_date:. Searches
        # subjects, senders and recipients.
        def search(inbox_id, options = {})
          Millionsend::Request.new(
            method: :get, path: "#{Inboxes.member_path(inbox_id)}/threads/search",
            query: Millionsend::Util.csv_query(options)
          ).perform
        end

        # GET /inboxes/:id/threads/:thread_id
        def get(inbox_id, thread_id)
          Millionsend::Request.new(method: :get, path: member_path(inbox_id, thread_id)).perform
        end

        # PATCH /inboxes/:id/threads/:thread_id — read, folder ("inbox",
        # "archive", "spam" or "trash"), label_id.
        def update(inbox_id, thread_id, params)
          Millionsend::Request.new(method: :patch, path: member_path(inbox_id, thread_id), body: params).perform
        end

        # DELETE /inboxes/:id/threads/:thread_id — moves it to trash, purged
        # after 30 days; deleted is false when it was there already.
        def remove(inbox_id, thread_id)
          Millionsend::Request.new(method: :delete, path: member_path(inbox_id, thread_id)).perform
        end

        def member_path(inbox_id, thread_id)
          "#{Inboxes.member_path(inbox_id)}/threads/#{Millionsend::Util.encode(thread_id)}"
        end
      end

      # The messages of one thread.
      module Emails
        class << self
          # GET .../threads/:thread_id/emails — limit:/after:/before:. Oldest
          # first; after: pages toward newer.
          def list(inbox_id, thread_id, options = {})
            Millionsend::Request.new(
              method: :get, path: "#{Threads.member_path(inbox_id, thread_id)}/emails",
              query: Millionsend::Util.list_query(options)
            ).perform
          end

          # GET .../threads/:thread_id/emails/:email_id
          def get(inbox_id, thread_id, email_id)
            Millionsend::Request.new(method: :get, path: member_path(inbox_id, thread_id, email_id)).perform
          end

          # POST .../emails/:email_id/reply — html/text, cc, bcc, subject,
          # reply_all, requires_approval. Returns { kind: "sent", data:
          # <sent email> }, or { kind: "draft", data: <draft> } when the
          # inbox's rules held it for approval (202). The trailing hash takes
          # idempotency_key, flat or under options:.
          def reply(inbox_id, thread_id, email_id, params, options = {})
            Millionsend::Request.new(
              method: :post, path: "#{member_path(inbox_id, thread_id, email_id)}/reply", body: params,
              **Millionsend::Util.request_options(options)
            ).perform_outcome
          end

          # POST .../emails/:email_id/forward — to (required), cc, bcc, a
          # html/text note, subject, requires_approval. Same result and options
          # as reply.
          def forward(inbox_id, thread_id, email_id, params, options = {})
            Millionsend::Request.new(
              method: :post, path: "#{member_path(inbox_id, thread_id, email_id)}/forward", body: params,
              **Millionsend::Util.request_options(options)
            ).perform_outcome
          end

          private

          def member_path(inbox_id, thread_id, email_id)
            "#{Threads.member_path(inbox_id, thread_id)}/emails/#{Millionsend::Util.encode(email_id)}"
          end
        end
      end
    end

    # Drafts, standalone or replies: sent on demand or held for approval.
    module Drafts
      class << self
        # GET /inboxes/:id/drafts — limit:/after:/before:. Unsent drafts, most
        # recently updated first.
        def list(inbox_id, options = {})
          Millionsend::Request.new(
            method: :get, path: "#{Inboxes.member_path(inbox_id)}/drafts", query: Millionsend::Util.list_query(options)
          ).perform
        end

        # POST /inboxes/:id/drafts — to, cc, bcc, subject, html, text, plus
        # thread_id with reply_to_email_id for a reply draft. An unsent reply
        # draft to the same email comes back instead of a new one.
        def create(inbox_id, params)
          Millionsend::Request.new(method: :post, path: "#{Inboxes.member_path(inbox_id)}/drafts", body: params).perform
        end

        # GET /inboxes/:id/drafts/:draft_id — also after it was sent.
        def get(inbox_id, draft_id)
          Millionsend::Request.new(method: :get, path: member_path(inbox_id, draft_id)).perform
        end

        # PATCH /inboxes/:id/drafts/:draft_id — nil clears to, cc, bcc,
        # subject, html or text; setting html or text replaces both.
        def update(inbox_id, draft_id, params)
          Millionsend::Request.new(method: :patch, path: member_path(inbox_id, draft_id), body: params).perform
        end

        # DELETE /inboxes/:id/drafts/:draft_id
        def remove(inbox_id, draft_id)
          Millionsend::Request.new(method: :delete, path: member_path(inbox_id, draft_id)).perform
        end

        # POST /inboxes/:id/drafts/:draft_id/send — no body. Returns { kind:
        # "sent", data: { object:, id:, thread_id:, email_id: } }, or { kind:
        # "draft", data: <draft> } when the rules hold it for approval (202).
        # The trailing hash takes idempotency_key, flat or under options:.
        def send(inbox_id, draft_id, options = {})
          Millionsend::Request.new(
            method: :post, path: "#{member_path(inbox_id, draft_id)}/send", **Millionsend::Util.request_options(options)
          ).perform_outcome
        end

        # POST /inboxes/:id/drafts/:draft_id/reject — approvers only; returns
        # the draft with status "rejected".
        def reject(inbox_id, draft_id)
          Millionsend::Request.new(method: :post, path: "#{member_path(inbox_id, draft_id)}/reject").perform
        end

        private

        def member_path(inbox_id, draft_id)
          "#{Inboxes.member_path(inbox_id)}/drafts/#{Millionsend::Util.encode(draft_id)}"
        end
      end
    end
  end
end
