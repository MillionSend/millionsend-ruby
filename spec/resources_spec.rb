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

    it "cancel hits POST /emails/:id/cancel" do
      stub_request(:post, "https://api.test/emails/e1/cancel").to_return(ok)
      Millionsend::Emails.cancel("e1")
      expect(WebMock).to have_requested(:post, "https://api.test/emails/e1/cancel")
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
  end

  describe Millionsend::Audiences do
    it "covers create/get/list/remove" do
      stub_request(:post, "https://api.test/audiences").to_return(ok)
      Millionsend::Audiences.create({ name: "Users" })
      expect(WebMock).to have_requested(:post, "https://api.test/audiences").with(body: { "name" => "Users" })

      stub_request(:get, "https://api.test/audiences/a1").to_return(ok)
      Millionsend::Audiences.get("a1")
      expect(WebMock).to have_requested(:get, "https://api.test/audiences/a1")

      stub_request(:get, "https://api.test/audiences").with(query: { "limit" => "10" }).to_return(list_ok)
      Millionsend::Audiences.list(limit: 10)
      expect(WebMock).to have_requested(:get, "https://api.test/audiences").with(query: { "limit" => "10" })

      stub_request(:delete, "https://api.test/audiences/a1").to_return(ok)
      Millionsend::Audiences.remove("a1")
      expect(WebMock).to have_requested(:delete, "https://api.test/audiences/a1")
    end
  end

  describe Millionsend::Contacts do
    it "creates audience-scoped and top-level, stripping audience_id from the body" do
      stub_request(:post, "https://api.test/audiences/a1/contacts").to_return(ok)
      Millionsend::Contacts.create({ audience_id: "a1", email: "c@x.dev", first_name: "Ada" })
      expect(WebMock).to have_requested(:post, "https://api.test/audiences/a1/contacts")
        .with(body: { "email" => "c@x.dev", "first_name" => "Ada" })

      stub_request(:post, "https://api.test/contacts").to_return(ok)
      Millionsend::Contacts.create({ email: "c@x.dev" })
      expect(WebMock).to have_requested(:post, "https://api.test/contacts").with(body: { "email" => "c@x.dev" })
    end

    it "addresses by id, by email, and audience-scoped" do
      stub_request(:get, "https://api.test/contacts/c1").to_return(ok)
      Millionsend::Contacts.get("c1")
      expect(WebMock).to have_requested(:get, "https://api.test/contacts/c1")

      stub_request(:get, "https://api.test/contacts/c%40x.dev").to_return(ok)
      Millionsend::Contacts.get("c@x.dev")
      expect(WebMock).to have_requested(:get, "https://api.test/contacts/c%40x.dev")

      stub_request(:get, "https://api.test/audiences/a1/contacts/c1").to_return(ok)
      Millionsend::Contacts.get("c1", audience_id: "a1")
      expect(WebMock).to have_requested(:get, "https://api.test/audiences/a1/contacts/c1")
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

      stub_request(:get, "https://api.test/audiences/a1/contacts").with(query: { "after" => "cur" }).to_return(list_ok)
      Millionsend::Contacts.list(audience_id: "a1", after: "cur")
      expect(WebMock).to have_requested(:get, "https://api.test/audiences/a1/contacts").with(query: { "after" => "cur" })
    end

    it "topics_update patches /contacts/:id/topics with a bare array" do
      stub_request(:patch, "https://api.test/contacts/c1/topics").to_return(ok)
      Millionsend::Contacts.topics_update("c1", [{ id: "t1", subscription: "opt_out" }])
      expect(WebMock).to have_requested(:patch, "https://api.test/contacts/c1/topics")
        .with(body: [{ "id" => "t1", "subscription" => "opt_out" }])
    end
  end

  describe Millionsend::Topics do
    it "covers create/get/list/remove" do
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

      stub_request(:delete, "https://api.test/topics/t1").to_return(ok)
      Millionsend::Topics.remove("t1")
      expect(WebMock).to have_requested(:delete, "https://api.test/topics/t1")
    end
  end

  describe Millionsend::Broadcasts do
    it "covers the full lifecycle" do
      stub_request(:post, "https://api.test/broadcasts").to_return(ok)
      Millionsend::Broadcasts.create({ audience_id: "a1", from: "a@x.dev", subject: "News", html: "<p>hi</p>" })
      expect(WebMock).to have_requested(:post, "https://api.test/broadcasts")
        .with(body: { "audience_id" => "a1", "from" => "a@x.dev", "subject" => "News", "html" => "<p>hi</p>" })

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
  end

  describe Millionsend::Segments do
    it "covers create/get/list/update/remove on /segments2" do
      filter = { match: "all", conditions: [{ field: "email", op: "is_set" }] }

      stub_request(:post, "https://api.test/segments2").to_return(ok)
      Millionsend::Segments.create({ name: "Active", audience_id: "a1", filter: filter })
      expect(WebMock).to have_requested(:post, "https://api.test/segments2").with(
        body: {
          "name" => "Active", "audience_id" => "a1",
          "filter" => { "match" => "all", "conditions" => [{ "field" => "email", "op" => "is_set" }] }
        }
      )

      stub_request(:get, "https://api.test/segments2/s1").to_return(ok)
      Millionsend::Segments.get("s1")
      expect(WebMock).to have_requested(:get, "https://api.test/segments2/s1")

      stub_request(:get, "https://api.test/segments2").with(query: { "before" => "cur" }).to_return(list_ok)
      Millionsend::Segments.list(before: "cur")
      expect(WebMock).to have_requested(:get, "https://api.test/segments2").with(query: { "before" => "cur" })

      stub_request(:patch, "https://api.test/segments2/s1").to_return(ok)
      Millionsend::Segments.update("s1", { name: "Renamed" })
      expect(WebMock).to have_requested(:patch, "https://api.test/segments2/s1").with(body: { "name" => "Renamed" })

      stub_request(:delete, "https://api.test/segments2/s1").to_return(ok)
      Millionsend::Segments.remove("s1")
      expect(WebMock).to have_requested(:delete, "https://api.test/segments2/s1")
    end
  end
end
