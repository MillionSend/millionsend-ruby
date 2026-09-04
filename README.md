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

Params are symbol-keyed hashes and go on the wire **exactly as given** — nothing is
filtered or renamed (Ruby's snake_case is already the wire's snake_case: `reply_to`,
`scheduled_at`, `segment_id`). A `nil` value is sent as JSON `null`, which is how the API
clears a nullable field (`topic_id`, `first_name`, a template `alias`, …); omit the key to
leave it unchanged.

## Request options

`Emails.send`, `Batch.send` and `Contacts::Batch.create` take a trailing options hash, in
either of two shapes:

```ruby
Millionsend::Emails.send(payload, idempotency_key: "order-42")               # flat
Millionsend::Emails.send(payload, options: { idempotency_key: "order-42" })  # resend-ruby keyword shape
```

| option             | header / query        | where                                   |
| ------------------ | --------------------- | --------------------------------------- |
| `idempotency_key`  | `Idempotency-Key`     | any POST                                |
| `batch_validation` | `x-batch-validation`  | `Batch.send`, `Contacts::Batch.create`  |
| `on_conflict`      | `?on_conflict=`       | `Contacts::Batch.create`                |

`batch_validation` is `"strict"` by default (one invalid item rejects the whole batch) or
`"permissive"` (the valid subset is processed and the failures come back under `errors:`
as `[{ index:, message: }]`).

## Resources

### Emails

```ruby
Millionsend::Emails.send(payload, idempotency_key: "order-42") # POST  /emails
Millionsend::Emails.get(id)                                    # GET   /emails/:id (includes score: 0-10 or nil)
Millionsend::Emails.list(limit: 20, after: id)                 # GET   /emails
Millionsend::Emails.update(id, scheduled_at: "in 2 hours")     # PATCH /emails/:id (scheduled only)
Millionsend::Emails.cancel(id)                                 # POST  /emails/:id/cancel (scheduled only)
Millionsend::Emails.remove(id)                                 # DELETE /emails/:id
Millionsend::Emails.get_insights(id)                           # GET   /emails/:id/insights (404 until computed)

Millionsend::Batch.send([payload_a, payload_b], idempotency_key: "run-7", batch_validation: "permissive") # up to 100
```

The send payload accepts `from`, `to`, `subject`, `html`, `text`, `cc`, `bcc`, `reply_to`,
`scheduled_at`, `tags: [{ name:, value: }]`, `topic_id`, `headers: { "X-..." => "..." }`,
`attachments: [{ filename:, content: <base64>, content_type:, content_id:, path: }]` and
`template` (passed through; the server currently answers 422 for it). `to`, `cc`, `bcc` and
`reply_to` accept either a string or an array. `Emails.create` is an alias of `Emails.send`
(as is `Batch.create`), mirroring Resend. `Emails.update` also takes resend-ruby's single
hash: `Emails.update(email_id: id, scheduled_at: ...)`.

### Contacts

Contacts are team-global — one list per team, no audiences.

```ruby
contact = Millionsend::Contacts.create(
  email: "ada@acme.dev", first_name: "Ada", last_name: "Lovelace", unsubscribed: false,
  properties: { plan: "pro", seats: 3 },
  segments: [{ id: segment_id }],
  topics: [{ id: topic_id, subscription: "opt_in" }]
)
Millionsend::Contacts.get("ada@acme.dev") # by id or email
Millionsend::Contacts.update(id: contact[:id], unsubscribed: true, first_name: nil) # nil clears
Millionsend::Contacts.remove("ada@acme.dev")
Millionsend::Contacts.list(limit: 50)

# Topic subscriptions (granular unsubscribe) — mirrors resend's contacts.topics.update
Millionsend::Contacts.topics_update("ada@acme.dev", [{ id: topic_id, subscription: "opt_out" }])

# Segment membership
Millionsend::Contacts::Segments.add("ada@acme.dev", segment_id)    # POST   /contacts/:id/segments/:segment_id
Millionsend::Contacts::Segments.remove("ada@acme.dev", segment_id) # DELETE /contacts/:id/segments/:segment_id

# Bulk create (MillionSend extension) — up to 1000 per call
result = Millionsend::Contacts::Batch.create(
  [{ email: "a@acme.dev" }, { email: "b@acme.dev", first_name: "B" }],
  on_conflict: "upsert",          # "error" (default) | "skip" | "upsert"
  batch_validation: "permissive"  # "strict" (default) | "permissive"
)
result[:data]   # [{ index:, id:, status: "created" | "updated" | "skipped" }]
result[:counts] # { created:, updated:, skipped:, failed: }
result[:errors] # permissive mode only: [{ index:, message: }]
```

Contacts are addressable by id or email; when an `update` hash carries both, the email wins.
Emails are unique per team (case-insensitive) — a duplicate `create` raises
`Millionsend::ValidationError`.

### Contact properties

Typed custom fields for contacts. `key` and `type` are fixed at creation.

```ruby
prop = Millionsend::ContactProperties.create(key: "plan", type: "string", fallback_value: "free")
Millionsend::ContactProperties.get(prop[:id])
Millionsend::ContactProperties.list(limit: 50)
Millionsend::ContactProperties.update(prop[:id], fallback_value: nil) # nil clears
Millionsend::ContactProperties.remove(prop[:id])
```

### Topics

```ruby
Millionsend::Topics.create(name: "Product updates", default_subscription: "opt_in", visibility: "public")
Millionsend::Topics.get(id)
Millionsend::Topics.list    # bare { data: [...] } — topics are unpaginated
Millionsend::Topics.update(id, name: "Product news")
Millionsend::Topics.remove(id)
```

### Broadcasts

```ruby
broadcast = Millionsend::Broadcasts.create(
  name: "Launch",           # internal name shown in the dashboard
  segment_id: segment[:id], # optional; omit segment_id and topic_id to send to all contacts
  topic_id: topic[:id],     # optional; only contacts subscribed to it receive it
  from: "Acme <news@acme.dev>",
  subject: "Launch",
  html: "<p>Hi {{{FIRST_NAME|there}}}</p>",
  text: "Hi",
  reply_to: "hello@acme.dev",
  preview_text: "It's here",
  send: false,              # true sends (or, with scheduled_at, schedules) instead of saving a draft
  scheduled_at: nil         # "2026-09-01T09:00:00Z" or "in 1 hour" (requires send: true)
)
Millionsend::Broadcasts.list
Millionsend::Broadcasts.get(broadcast[:id])
Millionsend::Broadcasts.update(broadcast[:id], subject: "Launch 🚀", topic_id: nil) # draft only; nil clears
Millionsend::Broadcasts.send(broadcast[:id], scheduled_at: "2026-09-01T09:00:00Z") # omit to send now
Millionsend::Broadcasts.cancel(broadcast[:id]) # scheduled only
Millionsend::Broadcasts.remove(broadcast[:id]) # draft only
```

### Suppressions

Addresses the API refuses to send to. Entries are addressable by id or by email.

```ruby
Millionsend::Suppressions.add(email: "bounced@example.com", origin: "manual") # origin: bounce | complaint | manual | unsubscribe
Millionsend::Suppressions.get("bounced@example.com")
Millionsend::Suppressions.list(limit: 50, origin: "bounce")
Millionsend::Suppressions.remove("bounced@example.com")

Millionsend::Suppressions::Batch.add(emails: ["a@example.com", "b@example.com"], origin: "unsubscribe") # up to 1000
Millionsend::Suppressions::Batch.remove(emails: ["a@example.com"])   # or ids: [...]
```

`Suppressions.create` is an alias of `Suppressions.add`.

### Domains

```ruby
domain = Millionsend::Domains.create(
  name: "acme.dev",
  region: "us-east-1",          # optional; a deployment serves one region
  custom_return_path: "send",   # optional
  open_tracking: true, click_tracking: true, tracking_subdomain: "links"
)
domain[:records] # DNS records to publish, each with its own status
Millionsend::Domains.get(domain[:id])
Millionsend::Domains.list
Millionsend::Domains.verify(domain[:id]) # re-check DNS now
Millionsend::Domains.update(domain[:id], open_tracking: false, click_tracking: true, tracking_subdomain: nil) # nil clears
Millionsend::Domains.remove(domain[:id])
```

### Webhooks

```ruby
hook = Millionsend::Webhooks.create(
  endpoint: "https://acme.dev/hooks/millionsend",
  events: ["email.delivered", "email.bounced", "email.complained"],
  signing_secret: "whsec_..." # optional: reuse an existing secret so the receiver keeps verifying
)
hook[:signing_secret]
Millionsend::Webhooks.get(hook[:id]) # also returns signing_secret
Millionsend::Webhooks.list
Millionsend::Webhooks.update(hook[:id], events: ["email.opened"], status: "disabled")
Millionsend::Webhooks.remove(hook[:id])
```

Events: `email.sent`, `email.delivered`, `email.delivery_delayed`, `email.bounced`,
`email.complained`, `email.opened`, `email.clicked`, `deliverability.warning`,
`deliverability.paused`, `quota.warning`, `quota.reached`.

### API keys

```ruby
key = Millionsend::ApiKeys.create(name: "ci", permission: "sending_access", domain_id: domain[:id])
key[:token] # only returned here
Millionsend::ApiKeys.list
Millionsend::ApiKeys.remove(key[:id])
```

### Templates

Addressable by id or alias.

```ruby
tpl = Millionsend::Templates.create(name: "Welcome", html: "<p>Hi</p>", subject: "Welcome", text: "Hi", alias: "welcome")
Millionsend::Templates.get("welcome")
Millionsend::Templates.list
Millionsend::Templates.update("welcome", subject: nil, alias: nil) # nil clears subject/text/alias
Millionsend::Templates.publish(tpl[:id])   # templates are always published; kept as a no-op for compatibility
Millionsend::Templates.duplicate(tpl[:id]) # returns the copy's id
Millionsend::Templates.remove(tpl[:id])
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
Millionsend::Segments.contacts(segment[:id], limit: 50) # the contacts currently matching
Millionsend::Segments.update(segment[:id], name: "Pro tier")
Millionsend::Segments.remove(segment[:id])
```

### Usage (MillionSend extension)

```ruby
usage = Millionsend::Usage.get # GET /usage
usage[:plan]                   # "free" | "pro" | "scale" | nil (self-hosted)
usage[:limits]                 # { emails_per_day:, domains: } — nil means unlimited
usage[:today]                  # { emails_sent:, resets_at: }
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

Subclasses: `ValidationError`, `NotFoundError`, `MissingApiKeyError`, `InvalidApiKeyError`,
`RestrictedApiKeyError`, `SendingPausedError`, `BroadcastsPausedError`, `RateLimitExceededError`,
`DailyQuotaExceededError`, `InvalidIdempotentRequestError`, `ConcurrentIdempotentRequestsError`,
`InternalServerError`, and `ApplicationError` (the fallback for unknown names). Client-side and
transport failures that never reached the API raise `ApplicationError` with `#status_code == nil`.

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

Method names, nesting and payloads match; `options: { idempotency_key:, batch_validation: }`
works as in resend-ruby. Notes:

- **Member methods take the id first.** `update` on domains, webhooks, templates, contact
  properties, topics, broadcasts and segments is `update(id, params)` rather than a hash with
  `:id`; `Contacts.update` keeps resend's single-hash shape, and `Emails.update` accepts both.
- Resend's `Contacts.topics.update` becomes `Millionsend::Contacts.topics_update` (Ruby has no
  nested-module method on a module function). `Contacts::Segments` and `Suppressions::Batch`
  are nested modules as in resend-ruby.
- **No audiences** — contacts are team-global, so there is no `Audiences` resource and no
  `audience_id` params. The API's `/audiences/*` routes are a compatibility shim and are not
  part of this SDK. `Millionsend::Segments` is the dynamic-filter feature (`/segments`), not
  Resend's audiences alias.
- Not in the API (yet), so not here: broadcast recipients/clicked links, email sharing and
  metrics, contact imports, receiving, automations, logs, OAuth grants, webhook event replay.
- MillionSend extensions with no Resend counterpart: `Segments`, `Contacts::Batch`, `Usage`,
  `Deliverability`, `Emails.get_insights`, `Suppressions` `origin: "unsubscribe"`.

## License

MIT
