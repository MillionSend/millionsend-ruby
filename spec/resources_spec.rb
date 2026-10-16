# frozen_string_literal: true

# Method + path + body mapping for a representative call on every resource.
RSpec.describe "resource wiring" do
  def ok(body = '{"id":"x"}')
    { status: 200, body: body, headers: { "Content-Type" => "application/json" } }
  end

  def list_ok
    ok('{"object":"list","data":[],"has_more":false}')
  end

  describe Millionsend::Emails do
    it "get hits GET /emails/:id" do
      stub_request(:get, "https://api.test/emails/e1").to_return(ok)
      Millionsend::Emails.get("e1")
      expect(WebMock).to have_requested(:get, "https://api.test/emails/e1")
    end

    it "get returns score when present and null when the email has no insights" do
      stub_request(:get, "https://api.test/emails/e1").to_return(ok('{"object":"email","id":"e1","score":8.5}'))
      expect(Millionsend::Emails.get("e1")[:score]).to eq(8.5)

      stub_request(:get, "https://api.test/emails/e2").to_return(ok('{"object":"email","id":"e2","score":null}'))
      expect(Millionsend::Emails.get("e2")[:score]).to be_nil
    end

    it "get_insights hits GET /emails/:id/insights and returns the full report" do
      body = {
        object: "email_insights",
        email_id: "9f3a2b1c-0000-0000-0000-000000000001",
        score: 8.5,
        score_version: 1,
        band: "excellent",
        marketing: true,
        html_size_bytes: 12_345,
        computed_at: "2026-08-31T12:00:00.000Z",
        checks: [
          { id: "list_unsubscribe", severity: "critical", status: "fail", penalty: 1.25,
            detail: { header: "missing", docs: "https://x.test" } },
          { id: "plain_text_part", severity: "minor", status: "pass", penalty: 0 },
        ],
      }
      stub_request(:get, "https://api.test/emails/e1/insights").to_return(ok(JSON.generate(body)))

      res = Millionsend::Emails.get_insights("e1")
      expect(WebMock).to have_requested(:get, "https://api.test/emails/e1/insights")
      expect(res).to eq(body)
      expect(res[:checks][0][:detail]).to eq({ header: "missing", docs: "https://x.test" })
      expect(res[:checks][1]).not_to have_key(:detail)
    end

    it "get_insights tolerates unknown future band/severity/status values" do
      stub_request(:get, "https://api.test/emails/e1/insights").to_return(ok(
        '{"object":"email_insights","email_id":"e1","score":5.0,"score_version":9,"band":"stellar",' \
        '"marketing":false,"html_size_bytes":null,"computed_at":"2026-08-31T12:00:00.000Z",' \
        '"checks":[{"id":"brand_new_check","severity":"cosmic","status":"deferred","penalty":0}]}'
      ))

      res = Millionsend::Emails.get_insights("e1")
      expect(res[:band]).to eq("stellar")
      expect(res[:checks][0][:status]).to eq("deferred")
      expect(res[:html_size_bytes]).to be_nil
    end

    it "get_insights raises NotFoundError when insights are not available" do
      stub_request(:get, "https://api.test/emails/e1/insights").to_return(
        status: 404,
        body: '{"statusCode":404,"name":"not_found","message":"Insights not available"}',
        headers: { "Content-Type" => "application/json" }
      )

      expect { Millionsend::Emails.get_insights("e1") }.to raise_error(Millionsend::NotFoundError)
    end

    it "cancel hits POST /emails/:id/cancel" do
      stub_request(:post, "https://api.test/emails/e1/cancel").to_return(ok)
      Millionsend::Emails.cancel("e1")
      expect(WebMock).to have_requested(:post, "https://api.test/emails/e1/cancel")
    end

    it "send puts every REST field on the wire unchanged, including template and a null topic_id" do
      stub_request(:post, "https://api.test/emails").to_return(ok)
      payload = {
        from: "Acme <onboarding@acme.dev>",
        to: ["a@x.dev", "b@x.dev"],
        subject: "Full",
        html: "<p>hi</p>",
        text: "hi",
        cc: "cc@x.dev",
        bcc: ["bcc@x.dev"],
        reply_to: ["r1@x.dev", "r2@x.dev"],
        scheduled_at: "in 2 hours",
        tags: [{ name: "campaign", value: "launch" }],
        topic_id: nil,
        attachments: [{ filename: "a.txt", content: "aGVsbG8=", content_type: "text/plain",
                        content_id: "cid1", path: "https://x.dev/a.txt" }],
        headers: { "X-Entity-Ref-ID" => "42" },
        template: { id: "tpl_1", variables: { name: "Ada" } },
      }
      Millionsend::Emails.send(payload)

      expect(WebMock).to have_requested(:post, "https://api.test/emails").with(
        body: {
          "from" => "Acme <onboarding@acme.dev>",
          "to" => ["a@x.dev", "b@x.dev"],
          "subject" => "Full",
          "html" => "<p>hi</p>",
          "text" => "hi",
          "cc" => "cc@x.dev",
          "bcc" => ["bcc@x.dev"],
          "reply_to" => ["r1@x.dev", "r2@x.dev"],
          "scheduled_at" => "in 2 hours",
          "tags" => [{ "name" => "campaign", "value" => "launch" }],
          "topic_id" => nil,
          "attachments" => [{ "filename" => "a.txt", "content" => "aGVsbG8=", "content_type" => "text/plain",
                              "content_id" => "cid1", "path" => "https://x.dev/a.txt" }],
          "headers" => { "X-Entity-Ref-ID" => "42" },
          "template" => { "id" => "tpl_1", "variables" => { "name" => "Ada" } },
        }
      )
      expect(WebMock).to(have_requested(:post, "https://api.test/emails")
        .with { |req| JSON.parse(req.body).key?("topic_id") })
    end

    it "list hits GET /emails with pagination" do
      stub_request(:get, "https://api.test/emails").with(query: { "limit" => "5", "after" => "e9" }).to_return(list_ok)
      Millionsend::Emails.list(limit: 5, after: "e9")
      expect(WebMock).to have_requested(:get, "https://api.test/emails").with(query: { "limit" => "5", "after" => "e9" })
    end

    it "update patches /emails/:id with scheduled_at, positional or resend-ruby hash shape" do
      stub_request(:patch, "https://api.test/emails/e1").to_return(ok)
      Millionsend::Emails.update("e1", scheduled_at: "2999-01-01T00:00:00Z")
      Millionsend::Emails.update(email_id: "e1", scheduled_at: "2999-01-01T00:00:00Z")
      expect(WebMock).to have_requested(:patch, "https://api.test/emails/e1")
        .with(body: { "scheduled_at" => "2999-01-01T00:00:00Z" }).twice
    end

    it "remove hits DELETE /emails/:id" do
      stub_request(:delete, "https://api.test/emails/e1").to_return(ok)
      Millionsend::Emails.remove("e1")
      expect(WebMock).to have_requested(:delete, "https://api.test/emails/e1")
    end

    it "create is an alias of send that posts to /emails" do
      stub_request(:post, "https://api.test/emails").to_return(ok)
      Millionsend::Emails.create({ from: "a@x.dev", to: "b@x.dev", subject: "s", text: "t" })
      expect(WebMock).to have_requested(:post, "https://api.test/emails")
        .with(body: { "from" => "a@x.dev", "to" => "b@x.dev", "subject" => "s", "text" => "t" })
    end
  end

  describe Millionsend::Batch do
    it "posts a bare array to /emails/batch with an idempotency key" do
      stub_request(:post, "https://api.test/emails/batch").to_return(ok('{"data":[{"id":"1"},{"id":"2"}]}'))
      res = Millionsend::Batch.send(
        [{ from: "a@x.dev", to: "b@x.dev", subject: "1", text: "one" },
         { from: "a@x.dev", to: "c@x.dev", subject: "2", text: "two" }],
        idempotency_key: "batch-1"
      )

      expect(WebMock).to(have_requested(:post, "https://api.test/emails/batch")
        .with(headers: { "Idempotency-Key" => "batch-1" }) { |req| JSON.parse(req.body).is_a?(Array) })
      expect(res[:data].length).to eq(2)
    end

    it "sends x-batch-validation and returns permissive-mode errors" do
      stub_request(:post, "https://api.test/emails/batch").to_return(
        ok('{"data":[{"id":"1"}],"errors":[{"index":1,"message":"to: invalid"}]}')
      )
      res = Millionsend::Batch.send(
        [{ from: "a@x.dev", to: "b@x.dev", subject: "1", text: "one" }, { from: "a@x.dev", subject: "2" }],
        batch_validation: "permissive"
      )

      expect(WebMock).to have_requested(:post, "https://api.test/emails/batch")
        .with(headers: { "x-batch-validation" => "permissive" })
      expect(res[:errors]).to eq([{ index: 1, message: "to: invalid" }])
    end

    it "accepts the resend-ruby options: keyword shape and omits the header when unset" do
      stub_request(:post, "https://api.test/emails/batch").to_return(ok('{"data":[]}'))
      Millionsend::Batch.send([{ from: "a@x.dev", to: "b@x.dev", subject: "1", text: "one" }],
                              options: { idempotency_key: "k9", batch_validation: "strict" })
      expect(WebMock).to have_requested(:post, "https://api.test/emails/batch")
        .with(headers: { "Idempotency-Key" => "k9", "x-batch-validation" => "strict" })

      Millionsend::Batch.send([{ from: "a@x.dev", to: "b@x.dev", subject: "1", text: "one" }])
      expect(WebMock).to(have_requested(:post, "https://api.test/emails/batch")
        .with { |req| !req.headers.key?("X-Batch-Validation") && !req.headers.key?("Idempotency-Key") })
    end
  end

  describe Millionsend::Contacts do
    it "create posts to /contacts" do
      stub_request(:post, "https://api.test/contacts").to_return(ok)
      Millionsend::Contacts.create({ email: "c@x.dev", first_name: "Ada" })
      expect(WebMock).to have_requested(:post, "https://api.test/contacts")
        .with(body: { "email" => "c@x.dev", "first_name" => "Ada" })
    end

    it "addresses by id and by email" do
      stub_request(:get, "https://api.test/contacts/c1").to_return(ok)
      Millionsend::Contacts.get("c1")
      expect(WebMock).to have_requested(:get, "https://api.test/contacts/c1")

      stub_request(:get, "https://api.test/contacts/c%40x.dev").to_return(ok)
      Millionsend::Contacts.get("c@x.dev")
      expect(WebMock).to have_requested(:get, "https://api.test/contacts/c%40x.dev")
    end

    it "update sends only body fields; email wins for addressing and nil clears" do
      stub_request(:patch, "https://api.test/contacts/c%40x.dev").to_return(ok)
      Millionsend::Contacts.update({ email: "c@x.dev", id: "c1", first_name: nil, unsubscribed: true })
      expect(WebMock).to have_requested(:patch, "https://api.test/contacts/c%40x.dev")
        .with(body: { "first_name" => nil, "unsubscribed" => true })
    end

    it "remove and list" do
      stub_request(:delete, "https://api.test/contacts/c%40x.dev").to_return(ok)
      Millionsend::Contacts.remove("c@x.dev")
      expect(WebMock).to have_requested(:delete, "https://api.test/contacts/c%40x.dev")

      stub_request(:get, "https://api.test/contacts").with(query: { "after" => "cur" }).to_return(list_ok)
      Millionsend::Contacts.list(after: "cur")
      expect(WebMock).to have_requested(:get, "https://api.test/contacts").with(query: { "after" => "cur" })
    end

    it "remove sends ?erase=true when asked, flat or in the addressing hash, and no query otherwise" do
      stub_request(:delete, "https://api.test/contacts/c1").with(query: { "erase" => "true" }).to_return(ok)
      Millionsend::Contacts.remove("c1", erase: true)
      Millionsend::Contacts.remove(id: "c1", erase: true)
      expect(WebMock).to have_requested(:delete, "https://api.test/contacts/c1").with(query: { "erase" => "true" }).twice

      stub_request(:delete, "https://api.test/contacts/c1").to_return(ok)
      Millionsend::Contacts.remove("c1")
      Millionsend::Contacts.remove(id: "c1")
      expect(WebMock).to(have_requested(:delete, "https://api.test/contacts/c1").with { |req| req.uri.query.nil? }.twice)
    end

    it "list joins include: into one comma-separated query value and omits it when unset" do
      stub_request(:get, "https://api.test/contacts")
        .with(query: { "limit" => "100", "include" => "properties,topics" }).to_return(list_ok)
      Millionsend::Contacts.list(limit: 100, include: %w[properties topics])
      expect(WebMock).to have_requested(:get, "https://api.test/contacts")
        .with(query: { "limit" => "100", "include" => "properties,topics" })

      stub_request(:get, "https://api.test/contacts").to_return(list_ok)
      Millionsend::Contacts.list(include: [])
      expect(WebMock).to(have_requested(:get, "https://api.test/contacts") { |req| req.uri.query.nil? })
    end

    it "topics_update patches /contacts/:id/topics with a bare array" do
      stub_request(:patch, "https://api.test/contacts/c1/topics").to_return(ok)
      Millionsend::Contacts.topics_update("c1", [{ id: "t1", subscription: "opt_out" }])
      expect(WebMock).to have_requested(:patch, "https://api.test/contacts/c1/topics")
        .with(body: [{ "id" => "t1", "subscription" => "opt_out" }])
    end

    it "Topics.list hits GET /contacts/:id_or_email/topics with the email encoded and decodes the shape" do
      body = '{"object":"list","has_more":false,"data":[{"id":"9f3a2b1c-0000-0000-0000-000000000002",' \
             '"name":"Insights","description":null,"subscription":"opt_in","explicit":false,"visibility":"public"}]}'
      stub_request(:get, "https://api.test/contacts/c%2Bnews%40x.dev/topics").to_return(ok(body))
      res = Millionsend::Contacts::Topics.list(email: "c+news@x.dev")
      expect(WebMock).to have_requested(:get, "https://api.test/contacts/c%2Bnews%40x.dev/topics")
      expect(res).to eq({
        object: "list", has_more: false,
        data: [{ id: "9f3a2b1c-0000-0000-0000-000000000002", name: "Insights", description: nil,
                 subscription: "opt_in", explicit: false, visibility: "public" }],
      })

      stub_request(:get, "https://api.test/contacts/c1/topics").to_return(ok(body))
      Millionsend::Contacts::Topics.list("c1")
      expect(WebMock).to have_requested(:get, "https://api.test/contacts/c1/topics")
    end

    it "accepts resend-ruby's addressing hashes on get/remove, Topics.update and Segments" do
      stub_request(:get, "https://api.test/contacts/c1").to_return(ok)
      Millionsend::Contacts.get(id: "c1")
      expect(WebMock).to have_requested(:get, "https://api.test/contacts/c1")

      stub_request(:delete, "https://api.test/contacts/c%40x.dev").to_return(ok)
      Millionsend::Contacts.remove(email: "c@x.dev")
      expect(WebMock).to have_requested(:delete, "https://api.test/contacts/c%40x.dev")

      stub_request(:patch, "https://api.test/contacts/c%40x.dev/topics").to_return(ok)
      Millionsend::Contacts::Topics.update(email: "c@x.dev", topics: [{ id: "t1", subscription: "opt_in" }])
      expect(WebMock).to have_requested(:patch, "https://api.test/contacts/c%40x.dev/topics")
        .with(body: [{ "id" => "t1", "subscription" => "opt_in" }])

      stub_request(:post, "https://api.test/contacts/c1/segments/s1").to_return(ok)
      Millionsend::Contacts::Segments.add(contact_id: "c1", segment_id: "s1")
      expect(WebMock).to have_requested(:post, "https://api.test/contacts/c1/segments/s1")

      stub_request(:delete, "https://api.test/contacts/c%40x.dev/segments/s1").to_return(ok)
      Millionsend::Contacts::Segments.remove(email: "c@x.dev", segment_id: "s1")
      expect(WebMock).to have_requested(:delete, "https://api.test/contacts/c%40x.dev/segments/s1")
    end

    it "create passes segments and topics through" do
      stub_request(:post, "https://api.test/contacts").to_return(ok)
      Millionsend::Contacts.create({
        email: "c@x.dev", first_name: "Ada", last_name: "L", unsubscribed: false,
        properties: { plan: "pro", seats: 3 }, segments: [{ id: "s1" }],
        topics: [{ id: "t1", subscription: "opt_in" }],
      })
      expect(WebMock).to have_requested(:post, "https://api.test/contacts").with(
        body: {
          "email" => "c@x.dev", "first_name" => "Ada", "last_name" => "L", "unsubscribed" => false,
          "properties" => { "plan" => "pro", "seats" => 3 }, "segments" => [{ "id" => "s1" }],
          "topics" => [{ "id" => "t1", "subscription" => "opt_in" }],
        }
      )
    end

    it "Batch.create posts a bare array to /contacts/batch with on_conflict and the validation header" do
      stub_request(:post, "https://api.test/contacts/batch").with(query: { "on_conflict" => "upsert" }).to_return(ok(
        '{"data":[{"object":"contact","index":0,"id":"c1","status":"created"}],' \
        '"counts":{"created":1,"updated":0,"skipped":0,"failed":1},' \
        '"errors":[{"index":1,"statusCode":422,"name":"validation_error","message":"email: invalid"}]}'
      ))
      res = Millionsend::Contacts::Batch.create(
        [{ email: "c@x.dev" }, { email: "nope" }],
        on_conflict: "upsert", batch_validation: "permissive", idempotency_key: "cb-1"
      )

      expect(WebMock).to(have_requested(:post, "https://api.test/contacts/batch")
        .with(query: { "on_conflict" => "upsert" },
              headers: { "x-batch-validation" => "permissive", "Idempotency-Key" => "cb-1" },
              body: [{ "email" => "c@x.dev" }, { "email" => "nope" }]))
      expect(res[:data]).to eq([{ object: "contact", index: 0, id: "c1", status: "created" }])
      expect(res[:counts]).to eq({ created: 1, updated: 0, skipped: 0, failed: 1 })
      expect(res[:errors]).to eq([{ index: 1, statusCode: 422, name: "validation_error", message: "email: invalid" }])
    end

    it "Batch.create omits on_conflict and the header by default, also under options:" do
      stub_request(:post, "https://api.test/contacts/batch").to_return(ok('{"data":[],"counts":{}}'))
      stub_request(:post, "https://api.test/contacts/batch").with(query: { "on_conflict" => "skip" }).to_return(ok('{"data":[],"counts":{}}'))
      Millionsend::Contacts::Batch.create([{ email: "c@x.dev" }])
      Millionsend::Contacts::Batch.create([{ email: "c@x.dev" }], options: { on_conflict: "skip" })

      expect(WebMock).to(have_requested(:post, "https://api.test/contacts/batch")
        .with { |req| req.uri.query.nil? && !req.headers.key?("X-Batch-Validation") })
      expect(WebMock).to have_requested(:post, "https://api.test/contacts/batch").with(query: { "on_conflict" => "skip" })
    end

    it "preferences_link posts to /contacts/:id_or_email/preferences-link with no body" do
      body = '{"object":"preferences_link","contact":"9f3a2b1c-0000-0000-0000-000000000001","url":"https://app.test/unsubscribe/tok"}'
      stub_request(:post, "https://api.test/contacts/c%2Bnews%40x.dev/preferences-link").to_return(ok(body))
      res = Millionsend::Contacts.preferences_link("c+news@x.dev")
      expect(WebMock).to(have_requested(:post, "https://api.test/contacts/c%2Bnews%40x.dev/preferences-link")
        .with { |req| req.body.nil? || req.body.empty? })
      expect(res).to eq({ object: "preferences_link", contact: "9f3a2b1c-0000-0000-0000-000000000001",
                          url: "https://app.test/unsubscribe/tok" })

      stub_request(:post, "https://api.test/contacts/c1/preferences-link").to_return(ok(body))
      Millionsend::Contacts.preferences_link(id: "c1")
      expect(WebMock).to have_requested(:post, "https://api.test/contacts/c1/preferences-link")
    end

    it "Batch.remove posts ids or emails to /contacts/batch/remove" do
      stub_request(:post, "https://api.test/contacts/batch/remove")
        .to_return(ok('{"data":[{"object":"contact","contact":"c1","deleted":true}]}'))
      res = Millionsend::Contacts::Batch.remove({ ids: %w[c1 c2] })
      Millionsend::Contacts::Batch.remove({ emails: ["a@x.dev"] })
      Millionsend::Contacts::Batch.remove(emails: ["b@x.dev"], erase: true)
      expect(WebMock).to have_requested(:post, "https://api.test/contacts/batch/remove")
        .with(body: { "ids" => %w[c1 c2] })
      expect(WebMock).to have_requested(:post, "https://api.test/contacts/batch/remove")
        .with(body: { "emails" => ["a@x.dev"] })
      expect(WebMock).to have_requested(:post, "https://api.test/contacts/batch/remove")
        .with(body: { "emails" => ["b@x.dev"], "erase" => true })
      expect(res[:data]).to eq([{ object: "contact", contact: "c1", deleted: true }])
    end

    it "Batch.get posts ids and emails to /contacts/batch/get and returns data plus missing" do
      stub_request(:post, "https://api.test/contacts/batch/get").to_return(ok(
        '{"object":"list","data":[{"object":"contact","id":"c1","email":"a@x.dev","first_name":null,"last_name":null,' \
        '"created_at":"2026-01-01T00:00:00.000Z","unsubscribed":false,' \
        '"properties":{"plan":{"type":"string","value":"pro"},"seats":{"type":"number","value":3}},' \
        '"topics":[{"id":"t1","name":"News","description":null,"subscription":"opt_in","explicit":false,"visibility":"public"}]}],' \
        '"missing":[{"index":1,"email":"ghost@x.dev"},{"index":3,"id":"c4"}]}'
      ))
      res = Millionsend::Contacts::Batch.get(
        ["c1", "ghost@x.dev", { email: "b@x.dev" }, { contact_id: "c4" }, { id: "c5" }],
        include: %w[properties topics]
      )
      expect(WebMock).to have_requested(:post, "https://api.test/contacts/batch/get").with(
        body: {
          "contacts" => [{ "id" => "c1" }, { "email" => "ghost@x.dev" }, { "email" => "b@x.dev" }, { "id" => "c4" }, { "id" => "c5" }],
          "include" => %w[properties topics],
        }
      )
      expect(res[:data].first).to include(object: "contact", id: "c1", email: "a@x.dev", unsubscribed: false)
      expect(res[:data].first[:properties]).to eq(plan: { type: "string", value: "pro" }, seats: { type: "number", value: 3 })
      expect(res[:data].first[:topics]).to eq([{ id: "t1", name: "News", description: nil, subscription: "opt_in",
                                                 explicit: false, visibility: "public" }])
      expect(res[:missing]).to eq([{ index: 1, email: "ghost@x.dev" }, { index: 3, id: "c4" }])
    end

    it "Batch.get leaves include out of the body when unset" do
      stub_request(:post, "https://api.test/contacts/batch/get").to_return(ok('{"object":"list","data":[],"missing":[]}'))
      res = Millionsend::Contacts::Batch.get([{ id: "c1" }])
      expect(WebMock).to have_requested(:post, "https://api.test/contacts/batch/get")
        .with(body: { "contacts" => [{ "id" => "c1" }] })
      expect(res).to eq(object: "list", data: [], missing: [])
    end

    it "Segments.add and .remove hit /contacts/:id/segments/:segment_id" do
      stub_request(:post, "https://api.test/contacts/c%40x.dev/segments/s1").to_return(ok)
      Millionsend::Contacts::Segments.add("c@x.dev", "s1")
      expect(WebMock).to have_requested(:post, "https://api.test/contacts/c%40x.dev/segments/s1")

      stub_request(:delete, "https://api.test/contacts/c1/segments/s1").to_return(ok)
      Millionsend::Contacts::Segments.remove("c1", "s1")
      expect(WebMock).to have_requested(:delete, "https://api.test/contacts/c1/segments/s1")
    end
  end

  describe Millionsend::Topics do
    it "covers create/get/list/update/remove" do
      stub_request(:post, "https://api.test/topics").to_return(ok)
      Millionsend::Topics.create({ name: "Product", default_subscription: "opt_in" })
      expect(WebMock).to have_requested(:post, "https://api.test/topics")
        .with(body: { "name" => "Product", "default_subscription" => "opt_in" })

      stub_request(:get, "https://api.test/topics/t1").to_return(ok)
      Millionsend::Topics.get("t1")
      expect(WebMock).to have_requested(:get, "https://api.test/topics/t1")

      stub_request(:get, "https://api.test/topics").to_return(ok('{"data":[]}'))
      Millionsend::Topics.list
      expect(WebMock).to have_requested(:get, "https://api.test/topics")

      stub_request(:patch, "https://api.test/topics/t1").to_return(ok)
      Millionsend::Topics.update("t1", { name: "Renamed", visibility: "public" })
      expect(WebMock).to have_requested(:patch, "https://api.test/topics/t1")
        .with(body: { "name" => "Renamed", "visibility" => "public" })

      stub_request(:delete, "https://api.test/topics/t1").to_return(ok)
      Millionsend::Topics.remove("t1")
      expect(WebMock).to have_requested(:delete, "https://api.test/topics/t1")
    end
  end

  describe Millionsend::Broadcasts do
    it "covers the full lifecycle" do
      stub_request(:post, "https://api.test/broadcasts").to_return(ok)
      Millionsend::Broadcasts.create({ segment_id: "s1", from: "a@x.dev", subject: "News", html: "<p>hi</p>" })
      expect(WebMock).to have_requested(:post, "https://api.test/broadcasts")
        .with(body: { "segment_id" => "s1", "from" => "a@x.dev", "subject" => "News", "html" => "<p>hi</p>" })

      stub_request(:get, "https://api.test/broadcasts/b1").to_return(ok)
      Millionsend::Broadcasts.get("b1")
      expect(WebMock).to have_requested(:get, "https://api.test/broadcasts/b1")

      stub_request(:get, "https://api.test/broadcasts").to_return(list_ok)
      Millionsend::Broadcasts.list
      expect(WebMock).to have_requested(:get, "https://api.test/broadcasts")

      stub_request(:patch, "https://api.test/broadcasts/b1").to_return(ok)
      Millionsend::Broadcasts.update("b1", { subject: "New" })
      expect(WebMock).to have_requested(:patch, "https://api.test/broadcasts/b1").with(body: { "subject" => "New" })

      stub_request(:post, "https://api.test/broadcasts/b1/send").to_return(ok)
      Millionsend::Broadcasts.send("b1", scheduled_at: "2999-01-01T00:00:00Z")
      expect(WebMock).to have_requested(:post, "https://api.test/broadcasts/b1/send")
        .with(body: { "scheduled_at" => "2999-01-01T00:00:00Z" })

      stub_request(:post, "https://api.test/broadcasts/b1/cancel").to_return(ok)
      Millionsend::Broadcasts.cancel("b1")
      expect(WebMock).to have_requested(:post, "https://api.test/broadcasts/b1/cancel")

      stub_request(:delete, "https://api.test/broadcasts/b1").to_return(ok)
      Millionsend::Broadcasts.remove("b1")
      expect(WebMock).to have_requested(:delete, "https://api.test/broadcasts/b1")
    end

    it "create passes every field through and update sends topic_id nil as JSON null" do
      stub_request(:post, "https://api.test/broadcasts").to_return(ok)
      Millionsend::Broadcasts.create({
        name: "Launch", segment_id: "s1", from: "a@x.dev", subject: "News", html: "<p>hi</p>", text: "hi",
        reply_to: "r@x.dev", preview_text: "pre", topic_id: "t1", send: true, scheduled_at: "in 1 hour",
      })
      expect(WebMock).to have_requested(:post, "https://api.test/broadcasts").with(
        body: {
          "name" => "Launch", "segment_id" => "s1", "from" => "a@x.dev", "subject" => "News", "html" => "<p>hi</p>",
          "text" => "hi", "reply_to" => "r@x.dev", "preview_text" => "pre", "topic_id" => "t1", "send" => true,
          "scheduled_at" => "in 1 hour",
        }
      )

      stub_request(:patch, "https://api.test/broadcasts/b1").to_return(ok)
      Millionsend::Broadcasts.update("b1", { topic_id: nil, preview_text: "p" })
      expect(WebMock).to(have_requested(:patch, "https://api.test/broadcasts/b1")
        .with { |req| req.body == '{"topic_id":null,"preview_text":"p"}' })
    end
  end

  describe Millionsend::Deliverability do
    it "get hits GET /deliverability and returns the account score" do
      body = {
        object: "deliverability",
        score: 8.7, band: "good",
        content_score: 8.2, outcome_score: 9.1,
        complaint_rate: 0.0002, hard_bounce_rate: 0.001,
        emails_sent: 12_345, scored_recipients: 23_456,
        window_days: 30, insufficient_outcome_data: false,
        guardrail_status: "ok", score_version: 1,
      }
      stub_request(:get, "https://api.test/deliverability").to_return(ok(JSON.generate(body)))

      expect(Millionsend::Deliverability.get).to eq(body)
      expect(WebMock).to have_requested(:get, "https://api.test/deliverability")
    end

    it "get keeps null scores nil when there is not enough data" do
      stub_request(:get, "https://api.test/deliverability").to_return(ok(
        '{"object":"deliverability","score":null,"band":null,"content_score":null,"outcome_score":null,' \
        '"complaint_rate":0,"hard_bounce_rate":0,"emails_sent":0,"scored_recipients":0,"window_days":30,' \
        '"insufficient_outcome_data":true,"guardrail_status":"ok","score_version":1}'
      ))

      res = Millionsend::Deliverability.get
      expect(res[:score]).to be_nil
      expect(res[:band]).to be_nil
      expect(res[:insufficient_outcome_data]).to be(true)
    end
  end

  describe Millionsend::Segments do
    it "covers create/get/list/contacts/update/remove on /segments" do
      filter = { match: "all", conditions: [{ field: "email", op: "is_set", value: nil }] }

      stub_request(:post, "https://api.test/segments").to_return(ok)
      Millionsend::Segments.create({ name: "Active", filter: filter })
      expect(WebMock).to have_requested(:post, "https://api.test/segments").with(
        body: {
          "name" => "Active",
          "filter" => { "match" => "all", "conditions" => [{ "field" => "email", "op" => "is_set", "value" => nil }] },
        }
      )

      stub_request(:get, "https://api.test/segments/s1").to_return(ok)
      Millionsend::Segments.get("s1")
      expect(WebMock).to have_requested(:get, "https://api.test/segments/s1")

      stub_request(:get, "https://api.test/segments").with(query: { "before" => "cur" }).to_return(list_ok)
      Millionsend::Segments.list(before: "cur")
      expect(WebMock).to have_requested(:get, "https://api.test/segments").with(query: { "before" => "cur" })

      stub_request(:get, "https://api.test/segments/s1/contacts").with(query: { "limit" => "10" }).to_return(list_ok)
      Millionsend::Segments.contacts("s1", limit: 10)
      expect(WebMock).to have_requested(:get, "https://api.test/segments/s1/contacts").with(query: { "limit" => "10" })

      stub_request(:get, "https://api.test/segments/s1/contacts").with(query: { "include" => "topics" }).to_return(list_ok)
      Millionsend::Segments.contacts("s1", include: [:topics])
      expect(WebMock).to have_requested(:get, "https://api.test/segments/s1/contacts").with(query: { "include" => "topics" })

      stub_request(:patch, "https://api.test/segments/s1").to_return(ok)
      Millionsend::Segments.update("s1", { name: "Renamed" })
      expect(WebMock).to have_requested(:patch, "https://api.test/segments/s1").with(body: { "name" => "Renamed" })

      stub_request(:delete, "https://api.test/segments/s1").to_return(ok)
      Millionsend::Segments.remove("s1")
      expect(WebMock).to have_requested(:delete, "https://api.test/segments/s1")
    end
  end

  describe Millionsend::Suppressions do
    it "add/create post to /suppressions with email and origin" do
      stub_request(:post, "https://api.test/suppressions").to_return(ok('{"object":"suppression","id":"sup1"}'))
      Millionsend::Suppressions.add({ email: "bad@x.dev", origin: "manual" })
      Millionsend::Suppressions.create({ email: "bad@x.dev" })
      expect(WebMock).to have_requested(:post, "https://api.test/suppressions")
        .with(body: { "email" => "bad@x.dev", "origin" => "manual" })
      expect(WebMock).to have_requested(:post, "https://api.test/suppressions").with(body: { "email" => "bad@x.dev" })
    end

    it "list passes pagination and origin as query" do
      stub_request(:get, "https://api.test/suppressions")
        .with(query: { "limit" => "5", "origin" => "bounce" }).to_return(list_ok)
      Millionsend::Suppressions.list(limit: 5, origin: "bounce")
      expect(WebMock).to have_requested(:get, "https://api.test/suppressions")
        .with(query: { "limit" => "5", "origin" => "bounce" })

      stub_request(:get, "https://api.test/suppressions").to_return(list_ok)
      Millionsend::Suppressions.list
      expect(WebMock).to(have_requested(:get, "https://api.test/suppressions").with { |req| req.uri.query.nil? })
    end

    it "get and remove address by id or email" do
      stub_request(:get, "https://api.test/suppressions/bad%40x.dev").to_return(ok)
      Millionsend::Suppressions.get("bad@x.dev")
      expect(WebMock).to have_requested(:get, "https://api.test/suppressions/bad%40x.dev")

      stub_request(:delete, "https://api.test/suppressions/sup1").to_return(ok)
      Millionsend::Suppressions.remove("sup1")
      expect(WebMock).to have_requested(:delete, "https://api.test/suppressions/sup1")
    end

    it "Batch.add and Batch.remove post to /suppressions/batch/*" do
      stub_request(:post, "https://api.test/suppressions/batch/add").to_return(ok('{"data":[{"object":"suppression","id":"1"}]}'))
      Millionsend::Suppressions::Batch.add({ emails: ["a@x.dev", "b@x.dev"], origin: "unsubscribe" })
      expect(WebMock).to have_requested(:post, "https://api.test/suppressions/batch/add")
        .with(body: { "emails" => ["a@x.dev", "b@x.dev"], "origin" => "unsubscribe" })

      stub_request(:post, "https://api.test/suppressions/batch/remove").to_return(ok('{"data":[]}'))
      Millionsend::Suppressions::Batch.remove({ emails: ["a@x.dev"] })
      Millionsend::Suppressions::Batch.remove({ ids: %w[sup1 sup2] })
      expect(WebMock).to have_requested(:post, "https://api.test/suppressions/batch/remove")
        .with(body: { "emails" => ["a@x.dev"] })
      expect(WebMock).to have_requested(:post, "https://api.test/suppressions/batch/remove")
        .with(body: { "ids" => %w[sup1 sup2] })
    end
  end

  describe Millionsend::Domains do
    it "covers create/get/list/update/verify/remove" do
      stub_request(:post, "https://api.test/domains").to_return(ok)
      Millionsend::Domains.create({ name: "acme.dev", region: "us-east-1", custom_return_path: "bounce",
                                    open_tracking: true, click_tracking: true, tracking_subdomain: "links" })
      expect(WebMock).to have_requested(:post, "https://api.test/domains").with(
        body: { "name" => "acme.dev", "region" => "us-east-1", "custom_return_path" => "bounce",
                "open_tracking" => true, "click_tracking" => true, "tracking_subdomain" => "links" }
      )

      stub_request(:get, "https://api.test/domains/d1").to_return(ok)
      Millionsend::Domains.get("d1")
      expect(WebMock).to have_requested(:get, "https://api.test/domains/d1")

      stub_request(:get, "https://api.test/domains").with(query: { "limit" => "3" }).to_return(list_ok)
      Millionsend::Domains.list(limit: 3)
      expect(WebMock).to have_requested(:get, "https://api.test/domains").with(query: { "limit" => "3" })

      stub_request(:patch, "https://api.test/domains/d1").to_return(ok)
      Millionsend::Domains.update("d1", { open_tracking: false, click_tracking: true, tracking_subdomain: nil })
      expect(WebMock).to(have_requested(:patch, "https://api.test/domains/d1")
        .with { |req| req.body == '{"open_tracking":false,"click_tracking":true,"tracking_subdomain":null}' })

      stub_request(:post, "https://api.test/domains/d1/verify").to_return(ok)
      Millionsend::Domains.verify("d1")
      expect(WebMock).to have_requested(:post, "https://api.test/domains/d1/verify")

      stub_request(:delete, "https://api.test/domains/d1").to_return(ok)
      Millionsend::Domains.remove("d1")
      expect(WebMock).to have_requested(:delete, "https://api.test/domains/d1")
    end

    it "lists the team's shared subdomain last with its sending mode, and it is read-only" do
      own = { id: "d1", name: "acme.dev", status: "verified", created_at: "2026-10-13T09:00:00.000Z", region: "us-east-1",
              open_tracking: true, click_tracking: true, tracking_subdomain: nil,
              capabilities: { sending: "enabled", receiving: "disabled" }, receiving_catch_all: false, shared: false }
      shared = { id: "sd1", name: "acme.agents.example", status: "verified", created_at: "2026-10-12T09:00:00.000Z",
                 region: "us-east-1", open_tracking: false, click_tracking: false, tracking_subdomain: nil,
                 capabilities: { sending: "enabled", receiving: "enabled" }, receiving_catch_all: false,
                 shared: true, sending_mode: "reply_only", sending_mode_reason: "plan" }
      stub_request(:get, "https://api.test/domains")
        .to_return(ok(JSON.generate({ object: "list", has_more: false, data: [own, shared] })))
      expect(Millionsend::Domains.list[:data]).to eq([own, shared])

      open_row = shared.merge(object: "domain", sending_mode: "open", sending_mode_reason: nil, records: [])
      stub_request(:get, "https://api.test/domains/sd1").to_return(ok(JSON.generate(open_row)))
      expect(Millionsend::Domains.get("sd1")).to include(shared: true, sending_mode_reason: nil, records: [])

      stub_request(:patch, "https://api.test/domains/sd1").to_return(
        status: 403, headers: { "Content-Type" => "application/json" },
        body: JSON.generate(statusCode: 403, name: "forbidden",
                            message: "acme.agents.example is your team's subdomain of the shared domain: it can't be changed or deleted")
      )
      expect { Millionsend::Domains.update("sd1", { open_tracking: true }) }
        .to raise_error(Millionsend::ForbiddenError) { |e| expect(e.status_code).to eq(403) }
    end
  end

  describe Millionsend::Webhooks do
    it "covers create/get/list/update/remove" do
      stub_request(:post, "https://api.test/webhooks").to_return(ok('{"object":"webhook","id":"w1","signing_secret":"whsec_x"}'))
      res = Millionsend::Webhooks.create({ endpoint: "https://x.dev/hook", events: ["email.sent", "email.bounced"],
                                           signing_secret: "whsec_abc" })
      expect(WebMock).to have_requested(:post, "https://api.test/webhooks").with(
        body: { "endpoint" => "https://x.dev/hook", "events" => ["email.sent", "email.bounced"], "signing_secret" => "whsec_abc" }
      )
      expect(res[:signing_secret]).to eq("whsec_x")

      stub_request(:get, "https://api.test/webhooks/w1")
        .to_return(ok('{"object":"webhook","id":"w1","signing_secret":"whsec_x","previous_secret_expires_at":null}'))
      hook = Millionsend::Webhooks.get("w1")
      expect(hook[:signing_secret]).to eq("whsec_x")
      expect(hook).to have_key(:previous_secret_expires_at)
      expect(hook[:previous_secret_expires_at]).to be_nil

      stub_request(:get, "https://api.test/webhooks").with(query: { "after" => "w0" }).to_return(list_ok)
      Millionsend::Webhooks.list(after: "w0")
      expect(WebMock).to have_requested(:get, "https://api.test/webhooks").with(query: { "after" => "w0" })

      stub_request(:patch, "https://api.test/webhooks/w1").to_return(ok)
      Millionsend::Webhooks.update("w1", { endpoint: "https://x.dev/h2", events: ["email.opened"], status: "disabled" })
      expect(WebMock).to have_requested(:patch, "https://api.test/webhooks/w1")
        .with(body: { "endpoint" => "https://x.dev/h2", "events" => ["email.opened"], "status" => "disabled" })

      stub_request(:delete, "https://api.test/webhooks/w1").to_return(ok)
      Millionsend::Webhooks.remove("w1")
      expect(WebMock).to have_requested(:delete, "https://api.test/webhooks/w1")
    end

    it "rotate posts to /webhooks/:id/rotate, {} by default" do
      body = '{"object":"webhook","id":"w1","signing_secret":"whsec_new","previous_secret_expires_at":"2026-01-02T00:00:00.000Z"}'
      stub_request(:post, "https://api.test/webhooks/w1/rotate").to_return(ok(body))
      res = Millionsend::Webhooks.rotate("w1")
      expect(WebMock).to have_requested(:post, "https://api.test/webhooks/w1/rotate").with(body: "{}")
      expect(res).to eq({ object: "webhook", id: "w1", signing_secret: "whsec_new",
                          previous_secret_expires_at: "2026-01-02T00:00:00.000Z" })

      Millionsend::Webhooks.rotate("w1", { signing_secret: "whsec_mine", overlap_hours: 0 })
      expect(WebMock).to have_requested(:post, "https://api.test/webhooks/w1/rotate")
        .with(body: { "signing_secret" => "whsec_mine", "overlap_hours" => 0 })
    end
  end

  describe Millionsend::ApiKeys do
    it "covers create/list/remove" do
      stub_request(:post, "https://api.test/api-keys").to_return(ok('{"id":"k1","token":"ms_secret"}'))
      res = Millionsend::ApiKeys.create({ name: "ci", permission: "sending_access", domain_id: "d1" })
      expect(WebMock).to have_requested(:post, "https://api.test/api-keys")
        .with(body: { "name" => "ci", "permission" => "sending_access", "domain_id" => "d1" })
      expect(res).to eq({ id: "k1", token: "ms_secret" })

      stub_request(:get, "https://api.test/api-keys").to_return(list_ok)
      Millionsend::ApiKeys.list
      expect(WebMock).to have_requested(:get, "https://api.test/api-keys")

      stub_request(:delete, "https://api.test/api-keys/k1").to_return(ok)
      Millionsend::ApiKeys.remove("k1")
      expect(WebMock).to have_requested(:delete, "https://api.test/api-keys/k1")
    end
  end

  describe Millionsend::Templates do
    it "covers create/get/list/update/publish/duplicate/remove, by id or alias" do
      stub_request(:post, "https://api.test/templates").to_return(ok)
      Millionsend::Templates.create({ name: "Welcome", html: "<p>hi</p>", subject: "Hi", text: "hi", alias: "welcome",
                                      from: "a@x.dev", reply_to: ["r@x.dev"],
                                      variables: [{ key: "name", type: "string", fallback_value: "there" }] })
      expect(WebMock).to have_requested(:post, "https://api.test/templates").with(
        body: { "name" => "Welcome", "html" => "<p>hi</p>", "subject" => "Hi", "text" => "hi", "alias" => "welcome",
                "from" => "a@x.dev", "reply_to" => ["r@x.dev"],
                "variables" => [{ "key" => "name", "type" => "string", "fallback_value" => "there" }] }
      )

      stub_request(:get, "https://api.test/templates/welcome").to_return(ok)
      Millionsend::Templates.get("welcome")
      expect(WebMock).to have_requested(:get, "https://api.test/templates/welcome")

      stub_request(:get, "https://api.test/templates").with(query: { "before" => "t0" }).to_return(list_ok)
      Millionsend::Templates.list(before: "t0")
      expect(WebMock).to have_requested(:get, "https://api.test/templates").with(query: { "before" => "t0" })

      stub_request(:patch, "https://api.test/templates/t1").to_return(ok)
      Millionsend::Templates.update("t1", { name: "W2", alias: nil, subject: nil, text: nil })
      expect(WebMock).to(have_requested(:patch, "https://api.test/templates/t1")
        .with { |req| req.body == '{"name":"W2","alias":null,"subject":null,"text":null}' })

      stub_request(:post, "https://api.test/templates/t1/publish").to_return(ok)
      Millionsend::Templates.publish("t1")
      expect(WebMock).to have_requested(:post, "https://api.test/templates/t1/publish")

      stub_request(:post, "https://api.test/templates/t1/duplicate").to_return(ok)
      Millionsend::Templates.duplicate("t1")
      expect(WebMock).to have_requested(:post, "https://api.test/templates/t1/duplicate")

      stub_request(:delete, "https://api.test/templates/welcome").to_return(ok)
      Millionsend::Templates.remove("welcome")
      expect(WebMock).to have_requested(:delete, "https://api.test/templates/welcome")
    end
  end

  describe Millionsend::ContactProperties do
    it "covers create/get/list/update/remove" do
      stub_request(:post, "https://api.test/contact-properties").to_return(ok)
      Millionsend::ContactProperties.create({ key: "plan", type: "string", fallback_value: "free" })
      expect(WebMock).to have_requested(:post, "https://api.test/contact-properties")
        .with(body: { "key" => "plan", "type" => "string", "fallback_value" => "free" })

      stub_request(:get, "https://api.test/contact-properties/p1").to_return(ok)
      Millionsend::ContactProperties.get("p1")
      expect(WebMock).to have_requested(:get, "https://api.test/contact-properties/p1")

      stub_request(:get, "https://api.test/contact-properties").with(query: { "limit" => "50" }).to_return(list_ok)
      Millionsend::ContactProperties.list(limit: 50)
      expect(WebMock).to have_requested(:get, "https://api.test/contact-properties").with(query: { "limit" => "50" })

      stub_request(:patch, "https://api.test/contact-properties/p1").to_return(ok)
      Millionsend::ContactProperties.update("p1", { fallback_value: nil })
      expect(WebMock).to(have_requested(:patch, "https://api.test/contact-properties/p1")
        .with { |req| req.body == '{"fallback_value":null}' })

      stub_request(:delete, "https://api.test/contact-properties/p1").to_return(ok)
      Millionsend::ContactProperties.remove("p1")
      expect(WebMock).to have_requested(:delete, "https://api.test/contact-properties/p1")
    end
  end

  describe Millionsend::Usage do
    it "get hits GET /usage" do
      body = { object: "usage", cloud: true, plan: "pro", limits: { emails_per_day: 50_000, domains: 10 },
               today: { emails_sent: 12, resets_at: "2026-09-05T00:00:00.000Z" },
               team: { id: "t1", name: "Acme" }, app_url: "https://app.x.dev" }
      stub_request(:get, "https://api.test/usage").to_return(ok(JSON.generate(body)))
      expect(Millionsend::Usage.get).to eq(body)
      expect(WebMock).to have_requested(:get, "https://api.test/usage")
    end
  end

  # Fixtures in the shapes of the inbox wire contract: Resend's fields plus
  # MillionSend's extension keys.
  def draft_body(status = "pending_approval")
    { object: "inbox_draft", id: "d1", type: "reply", to: ["ada@x.dev"], cc: [], bcc: [], subject: "Re: Hi",
      html: nil, text: "Thanks", thread_id: "t1", reply_to_email_id: "m1", email_id: nil,
      created_at: "2026-10-12T10:00:00.000Z", updated_at: "2026-10-12T10:00:00.000Z",
      status: status, approval_reasons: ["send_policy"], forward: false, decided_by: nil, decided_at: nil,
      expires_at: "2026-10-19T10:00:00.000Z" }
  end

  def inbox_body
    { object: "inbox", id: "i1", name: "Signup bot", email_address: "signup-bot-7f3k@acme.agents.example",
      domain_id: "sd1", receiving_address: nil, from_name: nil, unread: 2, drafts: 1,
      last_received: "2026-10-12T10:00:00.000Z", created_at: "2026-10-12T09:00:00.000Z",
      kind: "agent", shared: true, expires_at: nil, quarantined: 1, pending_approval: 1 }
  end

  def thread_body
    { object: "inbox_thread", id: "t1", subject: "Confirm your email", folder: "inbox",
      labels: [{ id: "l1", name: "Billing", color: "#FFAA00" }], read: false, quarantined: 0 }
  end

  describe Millionsend::Emails::Receiving do
    it "list puts every filter on the query and returns the long-poll's held ids" do
      query = { "limit" => "10", "before" => "r0", "wait" => "30", "since" => "2026-10-12T00:00:00Z",
                "inbox_id" => "i1", "to" => "bot@x.dev", "from" => "stripe.com", "subject_contains" => "code",
                "unread" => "true", "include_quarantined" => "true" }
      body = { object: "list", has_more: false, data: [],
               held: [{ id: "r1", inbox_id: "i1", reason: "quarantined", quarantine_reason: "not_allowlisted",
                        created_at: "2026-10-12T10:00:00.000Z" }] }
      stub_request(:get, "https://api.test/emails/receiving").with(query: query).to_return(ok(JSON.generate(body)))

      res = Millionsend::Emails::Receiving.list(limit: 10, before: "r0", wait: 30, since: "2026-10-12T00:00:00Z",
                                                inbox_id: "i1", to: "bot@x.dev", from: "stripe.com",
                                                subject_contains: "code", unread: true, include_quarantined: true)
      expect(res[:held]).to eq(body[:held])

      stub_request(:get, "https://api.test/emails/receiving").to_return(list_ok)
      Millionsend::Emails::Receiving.list
      expect(WebMock).to have_requested(:get, "https://api.test/emails/receiving").with(query: {})
    end

    it "list answers an unknown inbox_id with not_found, even with wait, and sends unread alone" do
      stub_request(:get, "https://api.test/emails/receiving").with(query: { "inbox_id" => "i9", "wait" => "30" }).to_return(
        status: 404, body: '{"statusCode":404,"name":"not_found","message":"Inbox not found."}',
        headers: { "Content-Type" => "application/json" }
      )
      expect { Millionsend::Emails::Receiving.list(inbox_id: "i9", wait: 30) }
        .to raise_error(Millionsend::NotFoundError) { |e| expect(e.status_code).to eq(404) }

      stub_request(:get, "https://api.test/emails/receiving").with(query: { "unread" => "false" }).to_return(list_ok)
      Millionsend::Emails::Receiving.list(unread: false)
      expect(WebMock).to have_requested(:get, "https://api.test/emails/receiving").with(query: { "unread" => "false" })
    end

    it "get passes html_format and keeps the extension fields, unknown values included" do
      body = { object: "email", id: "r1", from: "noreply@github.com", subject: "Your code", html_format: "cid",
               inbox_id: "i1", thread_id: "t1", spam_verdict: "pass", virus_verdict: nil, spam_score: 3,
               screening: { verdict: "clean", sender_trust: "external", quarantine_reason: nil, reasons: [],
                            injection_score: 2, phishing_score: nil, hidden_text_removed: true },
               extracted_text: "Your code is 482913",
               extracted: { kinds: ["code"], code: "482913", link: nil, link_domain_matches_sender: nil, ambiguous: false },
               brand_new_field: { verdict: "cosmic" } }
      stub_request(:get, "https://api.test/emails/receiving/r1").with(query: { "html_format" => "cid" })
                                                                .to_return(ok(JSON.generate(body)))
      expect(Millionsend::Emails::Receiving.get("r1", html_format: "cid")).to eq(body)

      stub_request(:get, "https://api.test/emails/receiving/r1").to_return(ok('{"object":"email","id":"r1"}'))
      Millionsend::Emails::Receiving.get("r1")
      expect(WebMock).to have_requested(:get, "https://api.test/emails/receiving/r1").with(query: {})
    end

    it "reply posts the body with an Idempotency-Key and tells a sent reply from a drafted one" do
      sent = { object: "email", id: "e9", thread_id: "t1", inbox_id: "i1" }
      stub_request(:post, "https://api.test/emails/receiving/r1/reply").to_return(ok(JSON.generate(sent)))
      params = { text: "Thanks", subject: "Re: Hi", cc: ["c@x.dev"], bcc: "b@x.dev", reply_all: true,
                 requires_approval: false, from: "bot@acme.dev", inbox_id: "i1" }
      res = Millionsend::Emails::Receiving.reply("r1", params, idempotency_key: "rk-1")
      expect(WebMock).to have_requested(:post, "https://api.test/emails/receiving/r1/reply").with(
        headers: { "Idempotency-Key" => "rk-1" },
        body: { "text" => "Thanks", "subject" => "Re: Hi", "cc" => ["c@x.dev"], "bcc" => "b@x.dev", "reply_all" => true,
                "requires_approval" => false, "from" => "bot@acme.dev", "inbox_id" => "i1" }
      )
      expect(res).to eq({ kind: "sent", data: sent })

      stub_request(:post, "https://api.test/emails/receiving/r1/reply")
        .to_return(status: 202, body: JSON.generate(draft_body), headers: { "Content-Type" => "application/json" })
      res = Millionsend::Emails::Receiving.reply("r1", { text: "Thanks" }, options: { idempotency_key: "rk-2" })
      expect(res[:kind]).to eq("draft")
      expect(res[:data][:approval_reasons]).to eq(["send_policy"])
    end

    it "forward posts to, mode and the note, and a refusal keeps its error name" do
      stub_request(:post, "https://api.test/emails/receiving/r1/forward").to_return(ok('{"object":"email","id":"e9"}'))
      Millionsend::Emails::Receiving.forward("r1", { to: ["ops@acme.dev"], text: "FYI", mode: "attachment" })
      expect(WebMock).to(have_requested(:post, "https://api.test/emails/receiving/r1/forward")
        .with(body: { "to" => ["ops@acme.dev"], "text" => "FYI", "mode" => "attachment" }) { |req| !req.headers.key?("Idempotency-Key") })

      stub_request(:post, "https://api.test/emails/receiving/r2/forward").to_return(
        status: 403, body: '{"statusCode":403,"name":"email_quarantined","message":"This email is quarantined"}',
        headers: { "Content-Type" => "application/json" }
      )
      expect { Millionsend::Emails::Receiving.forward("r2", { to: "ops@acme.dev" }) }
        .to raise_error(Millionsend::EmailQuarantinedError) { |e| expect([e.status_code, e.name]).to eq([403, "email_quarantined"]) }
    end

    it "remove erases with DELETE /emails/receiving/:id" do
      stub_request(:delete, "https://api.test/emails/receiving/r1").to_return(ok('{"object":"email","id":"r1","deleted":true}'))
      expect(Millionsend::Emails::Receiving.remove("r1")[:deleted]).to eq(true)
    end

    it "Attachments list and get take positional ids or resend-ruby's hashes" do
      stub_request(:get, "https://api.test/emails/receiving/r1/attachments").with(query: { "limit" => "5" }).to_return(list_ok)
      Millionsend::Emails::Receiving::Attachments.list("r1", limit: 5)
      Millionsend::Emails::Receiving::Attachments.list(email_id: "r1", limit: 5)
      expect(WebMock).to have_requested(:get, "https://api.test/emails/receiving/r1/attachments")
        .with(query: { "limit" => "5" }).twice

      stub_request(:get, "https://api.test/emails/receiving/r1/attachments/a1").to_return(ok)
      Millionsend::Emails::Receiving::Attachments.get("r1", "a1")
      Millionsend::Emails::Receiving::Attachments.get(email_id: "r1", id: "a1")
      expect(WebMock).to have_requested(:get, "https://api.test/emails/receiving/r1/attachments/a1").twice
    end
  end

  describe Millionsend::Inboxes do
    it "create posts every field, and an empty create posts {} for a shared-domain address" do
      stub_request(:post, "https://api.test/inboxes").to_return(ok(JSON.generate(inbox_body)))
      res = Millionsend::Inboxes.create(email_address: "bot@acme.dev", name: "Bot", from_name: "Acme Bot", forwarding: false,
                                        kind: "human", expires_in: "7d", safety: { accept_from: "allowlist", send_cap: nil })
      expect(WebMock).to(have_requested(:post, "https://api.test/inboxes").with do |req|
        req.body == '{"email_address":"bot@acme.dev","name":"Bot","from_name":"Acme Bot","forwarding":false,' \
                    '"kind":"human","expires_in":"7d","safety":{"accept_from":"allowlist","send_cap":null}}'
      end)
      expect(res).to eq(inbox_body)

      Millionsend::Inboxes.create
      expect(WebMock).to have_requested(:post, "https://api.test/inboxes").with(body: "{}")
    end

    it "create sends username and domain_id exactly as given" do
      stub_request(:post, "https://api.test/inboxes").to_return(ok(JSON.generate(inbox_body)))
      Millionsend::Inboxes.create(username: "leo")
      Millionsend::Inboxes.create(domain_id: "sd1")
      Millionsend::Inboxes.create(domain_id: "d1", username: "support")
      expect(WebMock).to have_requested(:post, "https://api.test/inboxes").with(body: '{"username":"leo"}')
      expect(WebMock).to have_requested(:post, "https://api.test/inboxes").with(body: '{"domain_id":"sd1"}')
      expect(WebMock).to have_requested(:post, "https://api.test/inboxes").with(body: '{"domain_id":"d1","username":"support"}')
    end

    it "covers list/get/update/remove, with an address as the id" do
      stub_request(:get, "https://api.test/inboxes").with(query: { "kind" => "agent", "limit" => "2" }).to_return(list_ok)
      Millionsend::Inboxes.list(kind: "agent", limit: 2)
      expect(WebMock).to have_requested(:get, "https://api.test/inboxes").with(query: { "kind" => "agent", "limit" => "2" })

      stub_request(:get, "https://api.test/inboxes/bot%2Bsales%40acme.dev").to_return(ok(JSON.generate(inbox_body)))
      expect(Millionsend::Inboxes.get("bot+sales@acme.dev")[:quarantined]).to eq(1)

      stub_request(:patch, "https://api.test/inboxes/i1").to_return(ok(JSON.generate(inbox_body)))
      Millionsend::Inboxes.update("i1", { name: "Renamed", from_name: "", expires_in: nil })
      expect(WebMock).to(have_requested(:patch, "https://api.test/inboxes/i1")
        .with { |req| req.body == '{"name":"Renamed","from_name":"","expires_in":null}' })

      stub_request(:delete, "https://api.test/inboxes/i1").to_return(ok('{"object":"inbox","id":"i1","deleted":true}'))
      expect(Millionsend::Inboxes.remove("i1")[:deleted]).to eq(true)
    end

    it "Safety get and update; nil send_cap goes out as null" do
      body = { object: "inbox_safety", inbox_id: "i1", accept_from: "verified", allowlist: [], owner_addresses: [],
               screening: true, extract_codes: true, send_policy: "reply_only", require_approval: false,
               private_codes: true, send_cap: 200, forward_to: [] }
      stub_request(:get, "https://api.test/inboxes/i1/safety").to_return(ok(JSON.generate(body)))
      expect(Millionsend::Inboxes::Safety.get("i1")).to eq(body)

      stub_request(:patch, "https://api.test/inboxes/i1/safety").to_return(ok(JSON.generate(body)))
      Millionsend::Inboxes::Safety.update("i1", { allowlist: ["*@stripe.com"], send_cap: nil })
      expect(WebMock).to(have_requested(:patch, "https://api.test/inboxes/i1/safety")
        .with { |req| req.body == '{"allowlist":["*@stripe.com"],"send_cap":null}' })
    end

    it "Codes.latest sends from, wait, max_age and since" do
      body = { object: "verification_code", status: "found", kind: "otp", code: "482913", url: nil,
               link_domain_matches_sender: nil, email_id: "r1", from: "noreply@github.com",
               received_at: "2026-10-12T10:00:00.000Z", sender_trust: "external" }
      query = { "from" => "github.com", "wait" => "20", "max_age" => "600" }
      stub_request(:get, "https://api.test/inboxes/i1/codes/latest").with(query: query).to_return(ok(JSON.generate(body)))
      expect(Millionsend::Inboxes::Codes.latest("i1", from: "github.com", wait: 20, max_age: 600)).to eq(body)

      since = { "since" => "2026-10-16T12:00:00.000Z" }
      stub_request(:get, "https://api.test/inboxes/i1/codes/latest").with(query: since).to_return(ok(JSON.generate(body)))
      Millionsend::Inboxes::Codes.latest("i1", since: "2026-10-16T12:00:00.000Z")
      expect(WebMock).to have_requested(:get, "https://api.test/inboxes/i1/codes/latest").with(query: since)
    end

    it "Quarantine list and release, {} by default" do
      stub_request(:get, "https://api.test/inboxes/i1/quarantine").with(query: { "limit" => "5" }).to_return(list_ok)
      Millionsend::Inboxes::Quarantine.list("i1", limit: 5)
      expect(WebMock).to have_requested(:get, "https://api.test/inboxes/i1/quarantine").with(query: { "limit" => "5" })

      body = { object: "inbox_release", inbox_id: "i1", email_id: "r1", released_at: "2026-10-12T10:00:00.000Z",
               trusted_sender: "ada@x.dev" }
      stub_request(:post, "https://api.test/inboxes/i1/quarantine/r1/release").to_return(ok(JSON.generate(body)))
      Millionsend::Inboxes::Quarantine.release("i1", "r1")
      expect(WebMock).to have_requested(:post, "https://api.test/inboxes/i1/quarantine/r1/release").with(body: "{}")
      expect(Millionsend::Inboxes::Quarantine.release("i1", "r1", trust_sender: true)).to eq(body)
      expect(WebMock).to have_requested(:post, "https://api.test/inboxes/i1/quarantine/r1/release")
        .with(body: { "trust_sender" => true })
    end

    it "Labels cover list/create/update/remove" do
      stub_request(:get, "https://api.test/inboxes/i1/labels")
        .to_return(ok('{"object":"list","data":[{"id":"l1","name":"Billing","color":"#FFAA00","created_at":"2026-10-12T10:00:00.000Z"}]}'))
      expect(Millionsend::Inboxes::Labels.list("i1")[:data][0][:color]).to eq("#FFAA00")

      stub_request(:post, "https://api.test/inboxes/i1/labels").to_return(ok('{"object":"inbox_label","id":"l1"}'))
      Millionsend::Inboxes::Labels.create("i1", { name: "Billing", color: "#FFAA00" })
      expect(WebMock).to have_requested(:post, "https://api.test/inboxes/i1/labels")
        .with(body: { "name" => "Billing", "color" => "#FFAA00" })

      stub_request(:patch, "https://api.test/inboxes/i1/labels/l1").to_return(ok('{"object":"inbox_label","id":"l1"}'))
      Millionsend::Inboxes::Labels.update("i1", "l1", { name: "Invoices" })
      expect(WebMock).to have_requested(:patch, "https://api.test/inboxes/i1/labels/l1").with(body: { "name" => "Invoices" })

      stub_request(:delete, "https://api.test/inboxes/i1/labels/l1").to_return(ok('{"object":"inbox_label","id":"l1","deleted":true}'))
      Millionsend::Inboxes::Labels.remove("i1", "l1")
      expect(WebMock).to have_requested(:delete, "https://api.test/inboxes/i1/labels/l1")
    end

    it "Threads list and search send arrays as one comma-separated value; quarantined only when asked" do
      item = { id: "t1", subject: "Invoice 42", from: "Stripe <billing@stripe.com>", to: ["bot@acme.dev"], cc: [], bcc: [],
               labels: [], message_count: 2, has_attachment: true, has_draft: false, read: true,
               received_at: "2026-10-12T10:00:00.000Z", folder: "inbox" }
      query = { "folders" => "inbox,archive", "labels" => "l1,l2", "read" => "false", "include_quarantined" => "true",
                "limit" => "20", "after" => "t0" }
      stub_request(:get, "https://api.test/inboxes/i1/threads").with(query: query)
                                                               .to_return(ok(JSON.generate({ object: "list", has_more: false, data: [item.merge(quarantined: 2)] })))
      res = Millionsend::Inboxes::Threads.list("i1", folders: %w[inbox archive], labels: %w[l1 l2], read: false,
                                                     include_quarantined: true, limit: 20, after: "t0")
      expect(WebMock).to have_requested(:get, "https://api.test/inboxes/i1/threads").with(query: query)
      expect(res[:data][0][:quarantined]).to eq(2)

      search = { "query" => "\"invoice 42\" -spam", "from" => "stripe.com,ada", "to" => "bot@acme.dev",
                 "has_attachment" => "true", "start_date" => "2026-10-01", "end_date" => "2026-10-12", "folders" => "sent" }
      found = item.merge(matched_email_id: "m2", highlights: { subject: ["**Invoice** 42"] })
      stub_request(:get, "https://api.test/inboxes/i1/threads/search").with(query: search)
                                                                      .to_return(ok(JSON.generate({ object: "list", has_more: false, data: [found] })))
      res = Millionsend::Inboxes::Threads.search("i1", query: "\"invoice 42\" -spam", from: ["stripe.com", "ada"],
                                                       to: ["bot@acme.dev"], has_attachment: true, start_date: "2026-10-01",
                                                       end_date: "2026-10-12", folders: ["sent"])
      expect(res[:data][0][:highlights]).to eq({ subject: ["**Invoice** 42"] })
      expect(res[:data][0]).not_to have_key(:quarantined)
    end

    it "Threads get/update/remove" do
      stub_request(:get, "https://api.test/inboxes/i1/threads/t1").to_return(ok(JSON.generate(thread_body)))
      expect(Millionsend::Inboxes::Threads.get("i1", "t1")).to eq(thread_body)

      stub_request(:patch, "https://api.test/inboxes/i1/threads/t1").to_return(ok(JSON.generate(thread_body)))
      Millionsend::Inboxes::Threads.update("i1", "t1", { read: true, folder: "archive", label_id: "l1" })
      expect(WebMock).to have_requested(:patch, "https://api.test/inboxes/i1/threads/t1")
        .with(body: { "read" => true, "folder" => "archive", "label_id" => "l1" })

      stub_request(:delete, "https://api.test/inboxes/i1/threads/t1").to_return(ok('{"object":"inbox_thread","id":"t1","deleted":false}'))
      expect(Millionsend::Inboxes::Threads.remove("i1", "t1")[:deleted]).to eq(false)
    end

    it "Threads::Emails list/get/reply/forward, a reply held as a draft included" do
      query = { "after" => "m1", "include_quarantined" => "true" }
      stub_request(:get, "https://api.test/inboxes/i1/threads/t1/emails").with(query: query).to_return(list_ok)
      Millionsend::Inboxes::Threads::Emails.list("i1", "t1", after: "m1", include_quarantined: true)
      expect(WebMock).to have_requested(:get, "https://api.test/inboxes/i1/threads/t1/emails").with(query: query)

      email = { id: "m1", direction: "inbound", from: "Ada <ada@x.dev>", to: ["bot@acme.dev"], cc: [], bcc: [], reply_to: [],
                subject: "Hi", message_id: "<a@x.dev>", html: nil, text: "Hello", attachments: [{ id: "a1", filename: nil, size: nil }],
                read: false, received_at: "2026-10-12T10:00:00.000Z", extracted_text: "Hello", spam_verdict: "gray",
                virus_verdict: "processing_failed",
                screening: { verdict: "suspicious", sender_trust: "unauthenticated", quarantine_reason: nil, reasons: [],
                             injection_score: nil, phishing_score: nil, hidden_text_removed: false } }
      stub_request(:get, "https://api.test/inboxes/i1/threads/t1/emails/m1").to_return(ok(JSON.generate(email)))
      expect(Millionsend::Inboxes::Threads::Emails.get("i1", "t1", "m1")).to eq(email)
      expect(WebMock).to have_requested(:get, "https://api.test/inboxes/i1/threads/t1/emails/m1").with(query: {})
      stub_request(:get, "https://api.test/inboxes/i1/threads/t1/emails/m1").with(query: { "include_quarantined" => "true" })
                                                                            .to_return(ok(JSON.generate(email)))
      Millionsend::Inboxes::Threads::Emails.get("i1", "t1", "m1", include_quarantined: true)
      expect(WebMock).to have_requested(:get, "https://api.test/inboxes/i1/threads/t1/emails/m1")
        .with(query: { "include_quarantined" => "true" })

      sent = email.merge(id: "m2", direction: "outbound", read: true, email_id: "m2", thread_id: "t1", inbox_id: "i1", status: "queued")
      stub_request(:post, "https://api.test/inboxes/i1/threads/t1/emails/m1/reply").to_return(ok(JSON.generate(sent)))
      res = Millionsend::Inboxes::Threads::Emails.reply("i1", "t1", "m1", { text: "Thanks", reply_all: true, requires_approval: true },
                                                        idempotency_key: "tr-1")
      expect(WebMock).to have_requested(:post, "https://api.test/inboxes/i1/threads/t1/emails/m1/reply").with(
        headers: { "Idempotency-Key" => "tr-1" }, body: { "text" => "Thanks", "reply_all" => true, "requires_approval" => true }
      )
      expect(res).to eq({ kind: "sent", data: sent })

      stub_request(:post, "https://api.test/inboxes/i1/threads/t1/emails/m1/forward")
        .to_return(status: 202, body: JSON.generate(draft_body), headers: { "Content-Type" => "application/json" })
      res = Millionsend::Inboxes::Threads::Emails.forward("i1", "t1", "m1", { to: "ops@acme.dev", cc: ["c@acme.dev"], subject: "Fwd: Hi" })
      expect(WebMock).to have_requested(:post, "https://api.test/inboxes/i1/threads/t1/emails/m1/forward")
        .with(body: { "to" => "ops@acme.dev", "cc" => ["c@acme.dev"], "subject" => "Fwd: Hi" })
      expect(res).to eq({ kind: "draft", data: draft_body })
    end

    it "Drafts cover list/create/get/update/remove/reject" do
      stub_request(:get, "https://api.test/inboxes/i1/drafts").with(query: { "limit" => "3" }).to_return(list_ok)
      Millionsend::Inboxes::Drafts.list("i1", limit: 3)
      expect(WebMock).to have_requested(:get, "https://api.test/inboxes/i1/drafts").with(query: { "limit" => "3" })

      stub_request(:post, "https://api.test/inboxes/i1/drafts").to_return(ok(JSON.generate(draft_body("draft"))))
      Millionsend::Inboxes::Drafts.create("i1", { to: ["ada@x.dev"], subject: "Re: Hi", text: "Thanks", thread_id: "t1",
                                                  reply_to_email_id: "m1" })
      expect(WebMock).to have_requested(:post, "https://api.test/inboxes/i1/drafts").with(
        body: { "to" => ["ada@x.dev"], "subject" => "Re: Hi", "text" => "Thanks", "thread_id" => "t1", "reply_to_email_id" => "m1" }
      )

      stub_request(:get, "https://api.test/inboxes/i1/drafts/d1").to_return(ok(JSON.generate(draft_body)))
      expect(Millionsend::Inboxes::Drafts.get("i1", "d1")[:status]).to eq("pending_approval")

      stub_request(:patch, "https://api.test/inboxes/i1/drafts/d1").to_return(ok(JSON.generate(draft_body("draft"))))
      Millionsend::Inboxes::Drafts.update("i1", "d1", { subject: nil, cc: [], html: "<p>Thanks</p>" })
      expect(WebMock).to(have_requested(:patch, "https://api.test/inboxes/i1/drafts/d1")
        .with { |req| req.body == '{"subject":null,"cc":[],"html":"<p>Thanks</p>"}' })

      stub_request(:delete, "https://api.test/inboxes/i1/drafts/d1").to_return(ok('{"object":"inbox_draft","id":"d1","deleted":true}'))
      Millionsend::Inboxes::Drafts.remove("i1", "d1")
      expect(WebMock).to have_requested(:delete, "https://api.test/inboxes/i1/drafts/d1")

      stub_request(:post, "https://api.test/inboxes/i1/drafts/d1/reject").to_return(ok(JSON.generate(draft_body("rejected"))))
      expect(Millionsend::Inboxes::Drafts.reject("i1", "d1")[:status]).to eq("rejected")
      expect(WebMock).to(have_requested(:post, "https://api.test/inboxes/i1/drafts/d1/reject").with { |req| req.body.to_s.empty? })
    end

    it "Drafts.send posts no body, takes an Idempotency-Key and reports a held draft" do
      sent = { object: "inbox_draft", id: "d1", thread_id: "t1", email_id: "e9" }
      stub_request(:post, "https://api.test/inboxes/i1/drafts/d1/send").to_return(ok(JSON.generate(sent)))
      expect(Millionsend::Inboxes::Drafts.send("i1", "d1", idempotency_key: "ds-1")).to eq({ kind: "sent", data: sent })
      expect(WebMock).to(have_requested(:post, "https://api.test/inboxes/i1/drafts/d1/send")
        .with(headers: { "Idempotency-Key" => "ds-1" }) { |req| req.body.to_s.empty? && !req.headers.key?("Content-Type") })

      stub_request(:post, "https://api.test/inboxes/i1/drafts/d2/send")
        .to_return(status: 202, body: JSON.generate(draft_body), headers: { "Content-Type" => "application/json" })
      expect(Millionsend::Inboxes::Drafts.send("i1", "d2")).to eq({ kind: "draft", data: draft_body })

      stub_request(:post, "https://api.test/inboxes/i1/drafts/d3/send").to_return(
        status: 403, body: '{"statusCode":403,"name":"approval_required","message":"A person must approve this draft"}',
        headers: { "Content-Type" => "application/json" }
      )
      expect { Millionsend::Inboxes::Drafts.send("i1", "d3") }
        .to raise_error(Millionsend::ApprovalRequiredError) { |e| expect(e.name).to eq("approval_required") }
    end
  end

  describe "inbox fields on existing resources" do
    it "passes receiving_catch_all, inbox_id and inbox_ids through" do
      stub_request(:patch, "https://api.test/domains/d1").to_return(ok('{"object":"domain","id":"d1","receiving_catch_all":true}'))
      expect(Millionsend::Domains.update("d1", { receiving_catch_all: true })[:receiving_catch_all]).to eq(true)
      expect(WebMock).to have_requested(:patch, "https://api.test/domains/d1").with(body: { "receiving_catch_all" => true })

      stub_request(:post, "https://api.test/api-keys").to_return(ok('{"id":"k1","token":"ms_x"}'))
      Millionsend::ApiKeys.create({ name: "agent", permission: "full_access", inbox_id: "i1" })
      expect(WebMock).to have_requested(:post, "https://api.test/api-keys")
        .with(body: { "name" => "agent", "permission" => "full_access", "inbox_id" => "i1" })

      stub_request(:post, "https://api.test/webhooks").to_return(ok('{"object":"webhook","id":"w1","signing_secret":"whsec_x"}'))
      Millionsend::Webhooks.create({ endpoint: "https://x.dev/h", events: ["email.received", "inbox.email.received"], inbox_ids: ["i1"] })
      expect(WebMock).to have_requested(:post, "https://api.test/webhooks").with(
        body: { "endpoint" => "https://x.dev/h", "events" => ["email.received", "inbox.email.received"], "inbox_ids" => ["i1"] }
      )

      stub_request(:patch, "https://api.test/webhooks/w1").to_return(ok('{"object":"webhook","id":"w1"}'))
      Millionsend::Webhooks.update("w1", { inbox_ids: nil })
      expect(WebMock).to(have_requested(:patch, "https://api.test/webhooks/w1").with { |req| req.body == '{"inbox_ids":null}' })
    end
  end
end
