# millionsend

Official Ruby SDK for [MillionSend](https://github.com/MillionSend/millionsend) — a
self-hostable, Resend-compatible email API on AWS SES.

The API is wire-compatible with Resend, and this gem deliberately mirrors the shape of
[`resend`](https://github.com/resend/resend-ruby), so migrating is mostly a find-and-replace:
swap the constant, set `base_url` to your instance.

## Install

```bash
gem install millionsend
```

Or in a `Gemfile`:

```ruby
gem "millionsend"
```

Requires Ruby 3.0+. Only the standard library is used at runtime (`net/http`, `json`).

## Quickstart

```ruby
require "millionsend"

Millionsend.api_key  = "ms_123"
Millionsend.base_url = "https://mail.acme.dev"

email = Millionsend::Emails.send(
  from: "Acme <onboarding@acme.dev>",
  to: "delivered@resend.dev",
  subject: "Hello from MillionSend",
  html: "<strong>It works!</strong>"
)

puts email[:id]
```

Every call returns a symbol-keyed `Hash` on success and raises a `Millionsend::Error`
on any non-2xx response (see [Error handling](#error-handling)).

## Configuration

```ruby
Millionsend.api_key  = "ms_123"                # falls back to ENV["MILLIONSEND_API_KEY"]
Millionsend.base_url = "https://mail.acme.dev" # falls back to ENV["MILLIONSEND_BASE_URL"],
                                               # then http://localhost:3001
Millionsend.allow_insecure_http = false        # accept a non-loopback http:// base_url
```

MillionSend is self-hosted, so there is no cloud default — **set `base_url` to your
deployment in production.** An explicitly assigned value always wins over the environment.
Plain `http://` is only accepted for loopback hosts (`localhost`, `127.0.0.1`, `::1`); any
other `http://` URL raises `Millionsend::ApplicationError` on the first call, since the API
key is sent as a bearer header. Set `allow_insecure_http = true` to talk to a non-TLS
instance elsewhere (e.g. inside a private network).
Params are symbol-keyed hashes and map straight to the wire (Ruby's snake_case is already
the wire's snake_case: `reply_to`, `scheduled_at`, `segment_id`).

## Resources

### Emails

```ruby
Millionsend::Emails.send(payload, idempotency_key: "order-42") # POST /emails
Millionsend::Emails.get(id)                                    # GET  /emails/:id (includes score: 0-10 or nil)
Millionsend::Emails.get_insights(id)                           # GET  /emails/:id/insights (404 until computed)
Millionsend::Emails.cancel(id)                                 # POST /emails/:id/cancel (scheduled only)

Millionsend::Batch.send([payload_a, payload_b], idempotency_key: "run-7") # up to 100
```

`to`, `cc`, `bcc` and `reply_to` accept either a string or an array. `Emails.create` is
an alias of `Emails.send` (as is `Batch.create`), mirroring Resend.

### Contacts

Contacts are team-global — one list per team, no audiences.

```ruby
contact = Millionsend::Contacts.create(email: "ada@acme.dev", first_name: "Ada",
                                       properties: { plan: "pro" })
Millionsend::Contacts.get("ada@acme.dev") # by id or email
Millionsend::Contacts.update(id: contact[:id], unsubscribed: true, first_name: nil) # nil clears
Millionsend::Contacts.remove("ada@acme.dev")
Millionsend::Contacts.list(limit: 50)

# Topic subscriptions (granular unsubscribe) — mirrors resend's contacts.topics.update
Millionsend::Contacts.topics_update("ada@acme.dev", [{ id: topic_id, subscription: "opt_out" }])
```

Contacts are addressable by id or email; when an `update` hash carries both, the email wins.
Emails are unique per team (case-insensitive) — a duplicate `create` raises
`Millionsend::ValidationError`.

### Topics

```ruby
Millionsend::Topics.create(name: "Product updates", default_subscription: "opt_in")
Millionsend::Topics.get(id)
Millionsend::Topics.list    # bare { data: [...] } — topics are unpaginated
Millionsend::Topics.remove(id)
```

### Broadcasts

```ruby
broadcast = Millionsend::Broadcasts.create(
  segment_id: segment[:id], # optional; omit segment_id and topic_id to send to all contacts
  from: "Acme <news@acme.dev>",
  subject: "Launch",
  html: "<p>Hi {{{FIRST_NAME|there}}}</p>"
)
Millionsend::Broadcasts.list
Millionsend::Broadcasts.get(broadcast[:id])
Millionsend::Broadcasts.update(broadcast[:id], subject: "Launch 🚀") # draft only
Millionsend::Broadcasts.send(broadcast[:id], scheduled_at: "2026-09-01T09:00:00Z") # omit to send now
Millionsend::Broadcasts.cancel(broadcast[:id]) # scheduled only
Millionsend::Broadcasts.remove(broadcast[:id]) # draft only
```

### Segments (MillionSend extension)

Dynamic segments are a saved filter over the team's contacts — a MillionSend superset with
no Resend equivalent.

```ruby
segment = Millionsend::Segments.create(
  name: "Pro plan",
  filter: { match: "all", conditions: [{ field: "property:plan", op: "equals", value: "pro" }] }
)
Millionsend::Segments.get(segment[:id]) # includes a live contact_count
Millionsend::Segments.list
Millionsend::Segments.update(segment[:id], name: "Pro tier")
Millionsend::Segments.remove(segment[:id])
```

### Deliverability (MillionSend extension)

Per-email best-practice insights and the account-level deliverability score.

```ruby
insights = Millionsend::Emails.get_insights(email[:id]) # score, band, checks: [{id:, severity:, status:, penalty:, detail:}]
account  = Millionsend::Deliverability.get              # GET /deliverability — trailing-30-day account score
puts account[:score] # 0-10 (one decimal) or nil when there is not enough data
```

Check ids and the band/severity/status values are an open set that grows across score
versions — treat them as strings, not a closed enum.

## Error handling

No `{ data, error }` tuple — a non-2xx response raises. The base class is `Millionsend::Error`,
which carries `#status_code`, `#name` (the stable snake_case discriminant), and `#message`.
Subclasses are keyed on `name`, so you can rescue a specific failure:

```ruby
begin
  Millionsend::Emails.get(id)
rescue Millionsend::NotFoundError => e
  warn "no such email: #{e.message}"
rescue Millionsend::Error => e
  warn "#{e.name} (#{e.status_code || 'transport'}): #{e.message}"
end
```

Subclasses: `ValidationError`, `NotFoundError`, `RestrictedApiKeyError`, `SendingPausedError`,
`InvalidIdempotentRequestError`, and `ApplicationError` (the fallback). Client-side and
transport failures that never reached the API raise with `#status_code == nil`.

## Migrating from Resend

```diff
- require "resend"
- Resend.api_key = "re_123"
- Resend::Emails.send(from: "...", to: "...", subject: "Hi", html: "<p>hi</p>")
+ require "millionsend"
+ Millionsend.api_key  = "ms_123"
+ Millionsend.base_url = "https://mail.acme.dev"
+ Millionsend::Emails.send(from: "...", to: "...", subject: "Hi", html: "<p>hi</p>")
```

Method names, nesting and payloads match. Notes:

- **Domains and API keys** are managed in the MillionSend dashboard, not via the API, so there
  are no `Domains` / `ApiKeys` resources here.
- Resend's `Contacts.topics.update` becomes `Millionsend::Contacts.topics_update` (Ruby has no
  nested-module method on a module function).
- **No audiences** — contacts are team-global, so there is no `Audiences` resource and no
  `audience_id` params. `Millionsend::Segments` is the dynamic-filter feature (`/segments`),
  not Resend's audiences alias.

## License

MIT
