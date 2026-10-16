# millionsend

Official Ruby SDK for [MillionSend](https://github.com/MillionSend/millionsend) — a
self-hostable, Resend-compatible email API on AWS SES.

The API is wire-compatible with Resend, and this gem deliberately mirrors the shape of
[`resend`](https://github.com/resend/resend-ruby), so migrating is mostly a find-and-replace:
swap the constant (and, on a self-hosted instance, set `base_url`).

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

Millionsend.api_key = "ms_123"
# Millionsend.base_url = "https://mail.acme.dev" # self-hosted only; defaults to MillionSend Cloud

email = Millionsend::Emails.send(
  from: "Acme <onboarding@acme.dev>",
  to: "success@simulator.amazonses.com",
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
                                               # then https://api.millionsend.com (Cloud)
Millionsend.allow_insecure_http = false        # accept a non-loopback http:// base_url
```

MillionSend Cloud works with just the API key; a self-hosted instance sets `base_url` to
its origin. An explicitly assigned value always wins over the environment.
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

`Emails.send`, `Batch.send`, `Contacts::Batch.create` and the receiving and inbox replies,
forwards and `Drafts.send` take a trailing options hash, in either of two shapes:

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
as `[{ index:, message: }]`; `Contacts::Batch.create` adds each failure's `statusCode:` and
`name:`).

## Pagination

Lists answer `{ object: "list", data: [...], has_more: }`, and the SDK never pages for you.
Most lists are newest first: `after:` takes the last id of a page and pages toward older
items, `before:` takes the first id and pages toward newer ones (a `before:` page is still
newest first). Threads come most recently active first, a thread's emails oldest first
(`after:` pages toward newer), drafts most recently updated first; labels and topics are
unpaginated.

```ruby
# Incremental sync: only what is newer than the newest id already stored
page = Millionsend::Emails.list(limit: 100, before: newest_id)
until page[:data].empty?
  store(page[:data])
  newest_id = page[:data].first[:id]
  break unless page[:has_more]

  page = Millionsend::Emails.list(limit: 100, before: newest_id)
end
```

A cursor whose item was deleted raises `ValidationError` (`NotFoundError` on the `Inboxes`
lists): start again without a cursor and stop at the ids you already have. Servers before
v0.13.0 listed oldest first; walking every page with `after:` returns every item on both.

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

`subject` takes up to 998 characters here, in batches and in broadcasts (inbox replies,
forwards and drafts take 2,000). A `to`, `cc` or `bcc` address whose domain can never receive
mail (`example.com`, `.test`, `.invalid`, a TLD that doesn't exist, …) raises `ValidationError`,
on replies, forwards and drafts too, and so does such an address on a new contact. To test
sending without emailing anyone, use `success@simulator.amazonses.com`.

`from` may be an inbox's address on the [shared domain](#the-shared-domain) while the shared row
in `Domains.list` has `sending_mode: "open"`: the inbox's exact `email_address` (no `+tag`),
no display name or its `from_name`, no `reply_to`, `attachments`, `headers` or `scheduled_at`,
and at most 10 distinct recipients across `to`, `cc` and `bcc`. `Batch.send` and broadcasts
never send from the shared domain: `InboxSendPolicyError`, or that item's entry in a
permissive batch's `errors:`.

### Receiving

Mail your domains receive: Resend's `Emails::Receiving` plus MillionSend's long-poll, server-side
reply and forward, and erase. Inbox-scoped keys never see mail held for screening or in quarantine.

```ruby
page  = Millionsend::Emails::Receiving.list(limit: 20)             # GET /emails/receiving
email = Millionsend::Emails::Receiving.get(id, html_format: "cid")  # GET /emails/receiving/:id
email[:extracted_text] # the visible text: hidden text and invisible characters removed
email[:screening]      # { verdict:, sender_trust:, quarantine_reason:, injection_score:, ... }
email[:extracted]      # { kinds:, code:, link:, ... } on verification mail
Millionsend::Emails::Receiving::Attachments.list(id)                # each with a signed download_url (1 hour)
Millionsend::Emails::Receiving::Attachments.get(id, attachment_id)  # also get(email_id:, id:) as in resend-ruby
Millionsend::Emails::Receiving.remove(id)                           # erase now (full-access keys)

# Long-poll: wait up to 50 s for the next match
page = Millionsend::Emails::Receiving.list(inbox_id: inbox[:id], from: "github.com", wait: 30)
page[:data] # what arrived
page[:held] # [{ id:, inbox_id:, reason:, quarantine_reason:, created_at: }] — matches held for screening or quarantine

# Reply and forward from the server, threaded
res = Millionsend::Emails::Receiving.reply(id, { text: "Thanks!" }, idempotency_key: "reply-#{id}")
res = Millionsend::Emails::Receiving.forward(id, { to: "ops@acme.dev", mode: "attachment" }) # the original as an .eml
```

List options go on the query as given: `limit`, `after`, `before`, `wait` (0–50), `since`,
`inbox_id` (an unknown one raises `NotFoundError` at once, even with `wait`), `to`, `from` (an
address, or a domain covering its subdomains), `subject_contains`, `unread` (with `inbox_id`,
or alone on an inbox-scoped key), and `include_quarantined` or `quarantined` (held mail too, or
only; full-access keys). `reply` also takes `subject`, `cc`, `bcc`, `reply_all`,
`requires_approval`, `from` and `inbox_id`.

`reply` and `forward` return `{ kind: "sent", data: { object: "email", id:, thread_id:, inbox_id: } }`,
or `{ kind: "draft", data: <draft> }` when an inbox's rules hold the message for a person to
approve (HTTP 202); the draft's `approval_reasons` say why.

### Inboxes (beta)

Addresses whose mail lands in threads, for an agent (`kind: "agent"`, the default: screening, code
extraction and send rules on) or for people (`kind: "human"`). Mirrors Resend's Inboxes beta;
`Safety`, `Codes` and `Quarantine` are MillionSend extensions.

```ruby
inbox = Millionsend::Inboxes.create(name: "Signup bot", username: "signup-bot") # signup-bot@<team>.<shared domain>
inbox = Millionsend::Inboxes.create(email_address: "support@acme.dev", kind: "human")
inbox = Millionsend::Inboxes.create(domain_id: domain[:id], username: "billing") # billing@<that domain>
Millionsend::Inboxes.list(kind: "agent")
Millionsend::Inboxes.get("support@acme.dev") # by id or address
Millionsend::Inboxes.update(inbox[:id], name: "Support", from_name: "Acme Support", expires_in: nil) # nil: never expires
Millionsend::Inboxes.remove(inbox[:id]) # also revokes its inbox-scoped keys

# Safety rules: who may write in and what an agent may send
Millionsend::Inboxes::Safety.get(inbox[:id])
Millionsend::Inboxes::Safety.update(inbox[:id], accept_from: "allowlist", allowlist: ["*@stripe.com"], send_cap: nil)

# Verification codes and sign-in links (links are never fetched); waits up to 50 s
code = Millionsend::Inboxes::Codes.latest(inbox[:id], from: "github.com", wait: 30, max_age: 600)
code[:status] # "found" | "none" | "ambiguous" | "timeout"
code[:code]   # "482913", or code[:url] for a sign-in link
# A second sign-in waits for its own code: only mail received after the one already used counts
Millionsend::Inboxes::Codes.latest(inbox[:id], from: "github.com", wait: 30, since: code[:received_at])

# Quarantine: held mail is kept and listed; agents see it only once a person releases it
Millionsend::Inboxes::Quarantine.list(inbox[:id])
Millionsend::Inboxes::Quarantine.release(inbox[:id], email_id, trust_sender: true) # also allowlists the sender

# Threads and their messages
Millionsend::Inboxes::Threads.list(inbox[:id], folders: ["inbox", "archive"], read: false)
Millionsend::Inboxes::Threads.search(inbox[:id], query: "invoice", from: ["stripe.com"])
Millionsend::Inboxes::Threads.get(inbox[:id], thread_id)
Millionsend::Inboxes::Threads.update(inbox[:id], thread_id, read: true, folder: "archive", label_id: label_id)
Millionsend::Inboxes::Threads.remove(inbox[:id], thread_id) # to trash, purged after 30 days
Millionsend::Inboxes::Threads::Emails.list(inbox[:id], thread_id) # oldest first; include_quarantined: true for held mail too
Millionsend::Inboxes::Threads::Emails.get(inbox[:id], thread_id, email_id)
res = Millionsend::Inboxes::Threads::Emails.reply(inbox[:id], thread_id, email_id, { text: "On it." }, idempotency_key: "k1")
Millionsend::Inboxes::Threads::Emails.forward(inbox[:id], thread_id, email_id, { to: "ops@acme.dev" })

# Labels
label = Millionsend::Inboxes::Labels.create(inbox[:id], name: "Billing", color: "#FFAA00")
Millionsend::Inboxes::Labels.list(inbox[:id])
Millionsend::Inboxes::Labels.update(inbox[:id], label[:id], name: "Invoices")
Millionsend::Inboxes::Labels.remove(inbox[:id], label[:id])

# Drafts
draft = Millionsend::Inboxes::Drafts.create(inbox[:id], to: ["ada@x.dev"], subject: "Hello", text: "Hi Ada")
Millionsend::Inboxes::Drafts.list(inbox[:id])
Millionsend::Inboxes::Drafts.get(inbox[:id], draft[:id])
Millionsend::Inboxes::Drafts.update(inbox[:id], draft[:id], subject: nil) # nil clears
Millionsend::Inboxes::Drafts.send(inbox[:id], draft[:id], idempotency_key: "draft-1")
Millionsend::Inboxes::Drafts.reject(inbox[:id], draft[:id]) # approvers only
Millionsend::Inboxes::Drafts.remove(inbox[:id], draft[:id])
```

Thread replies, forwards and `Drafts.send` return `{ kind: "sent", data: ... }`, or
`{ kind: "draft", data: <draft> }` when the inbox's rules hold the message for approval; an
agent's reply to a Reply-To at another organization is held with `approval_reasons` including
`"reply_to_redirect"`. An inbox-scoped key or an MCP token cannot send a draft that waits for
approval (`ApprovalRequiredError`); a person in the dashboard or a full-access team key can.
Arrays in list and search options (`folders`, `labels`, `from`, `to`, `cc`, `bcc`) go out as one
comma-separated value. With `include_quarantined: true` (full-access team keys), `Threads.list`
and `search` items carry `quarantined:`, the count of held messages. Inbox names take 1–320
characters. Resend's hosted agent settings (`/inboxes/:id/agent`) are not exposed: MillionSend
runs no agent.

#### The shared domain

Without `email_address`, an inbox gets an address on the team's subdomain of the instance's
shared domain, which needs no DNS. `username` picks the part before the @ (1–64 of
`a-z 0-9 . _ -`, starting and ending with a letter or digit), and it is random when omitted.
`domain_id` takes the id of a `Domains.list` row in place of `email_address`: the shared row
works like leaving it out, and one of your own domains needs `username`. Reserved names
(`postmaster`, `admin`, `support`, …), a `fwd-` prefix and brand look-alikes raise
`ValidationError`, and so does an address already in use, with status 409.

A chosen `username` or a shared inbox's `from_name` is reviewed first. While that review is
down, `create` and `update` raise `NameReviewUnavailableError` (503, `retry_after` 60), and so
does every shared or forwarding `create` while a new team's subdomain still waits for its own
review (`retry_after` 300); nothing was created, so retry once `e.retry_after` seconds have
passed. Too many names reviewed or refused in a day raise `RateLimitExceededError` until the next
UTC midnight. Inboxes never expire unless `expires_in` says so (`"1h"` to `"365d"`), but a
shared-domain inbox left unused for 90 days is deleted.

What a shared address may send follows the shared row's `sending_mode`: `"open"` starts
conversations (`Emails.send` too), `"reply_only"` replies inside its threads, and
`"receive_only"` sends nothing; an inbox whose name looks like a brand only replies, even under
`"open"`. Refusals raise `InboxSendPolicyError` (403), `InboxSendCapReachedError` (429, the
team's daily cap, with `retry_after` running to the next UTC midnight) or `ValidationError`
(more than 10 recipients). On a shared inbox, `Safety.update` accepts `send_policy: "open"` only
while the mode is `"open"` and refuses `"allowlist"`; `owner_addresses` don't make senders
trusted there, and `forward_to` copies go to members' sign-in addresses only.

### Contacts

Contacts are team-global — one list per team, no audiences.

```ruby
contact = Millionsend::Contacts.create(
  email: "ada@acme.dev", first_name: "Ada", last_name: "Lovelace", unsubscribed: false,
  properties: { plan: "pro", seats: 3 },
  segments: [{ id: segment_id }],
  topics: [{ id: topic_id, subscription: "opt_in" }]
)
Millionsend::Contacts.get("ada@acme.dev") # by id or email; also resend-ruby's get(id: ...) / get(email: ...)
Millionsend::Contacts.update(id: contact[:id], unsubscribed: true, first_name: nil) # nil clears
Millionsend::Contacts.remove("ada@acme.dev")              # the contact's emails stay in the send log
Millionsend::Contacts.remove("ada@acme.dev", erase: true) # ?erase=true — also scrubs the address from email
                                                          # history, event payloads and API logs (GDPR/LGPD)
Millionsend::Contacts.list(limit: 50)
# Bulk read (MillionSend extension): carry the property map and the topic subscriptions on every
# item, so an audience reads in one request per 100 contacts instead of one per contact
Millionsend::Contacts.list(limit: 100, include: ["properties", "topics"]) # ?include=properties,topics

# Topic subscriptions (granular unsubscribe) — PATCH /contacts/:id/topics
Millionsend::Contacts::Topics.update(email: "ada@acme.dev", topics: [{ id: topic_id, subscription: "opt_out" }]) # resend-ruby shape
Millionsend::Contacts.topics_update("ada@acme.dev", [{ id: topic_id, subscription: "opt_out" }])                 # positional
Millionsend::Contacts::Topics.list(email: "ada@acme.dev") # GET /contacts/:id/topics — every topic with its effective
                                                          # subscription (explicit: false when it is the topic's default)
                                                          # and its visibility ("public" | "private")

# Preference-center link (MillionSend extension) — POST /contacts/:id/preferences-link
link = Millionsend::Contacts.preferences_link("ada@acme.dev") # by id or email; also preferences_link(id: ...) / (email: ...)
link[:url] # the contact's hosted preference page; no expiry, so show it only to that contact

# Segment membership — POST / DELETE /contacts/:id/segments/:segment_id
Millionsend::Contacts::Segments.add("ada@acme.dev", segment_id)
Millionsend::Contacts::Segments.remove(contact_id: contact[:id], segment_id: segment_id) # resend-ruby shape

# Bulk create (MillionSend extension) — up to 1000 per call
result = Millionsend::Contacts::Batch.create(
  [{ email: "a@acme.dev" }, { email: "b@acme.dev", first_name: "B" }],
  on_conflict: "upsert",          # "error" (default) | "skip" | "upsert"
  batch_validation: "permissive"  # "strict" (default) | "permissive"
)
result[:data]   # [{ index:, id:, status: "created" | "updated" | "skipped" }]
result[:counts] # { created:, updated:, skipped:, failed: }
result[:errors] # permissive mode only: [{ index:, message: }]

# Bulk lookup (MillionSend extension) — up to 1000 contacts by id or email in one request, in
# request order; unknown entries are listed, not errors — one request against the rate limit
found = Millionsend::Contacts::Batch.get([contact[:id], "b@acme.dev", { email: "c@acme.dev" }], include: ["topics"])
found[:data]    # [{ object: "contact", id:, email:, first_name:, last_name:, created_at:, unsubscribed:, topics: }]
found[:missing] # [{ index:, email: }] / [{ index:, id: }] — request entries that matched nobody

# Bulk delete (MillionSend extension) — up to 1000 per call, exactly one of ids: / emails:
Millionsend::Contacts::Batch.remove(emails: ["a@acme.dev", "b@acme.dev"]) # or ids: [...]; emails stay in the log
Millionsend::Contacts::Batch.remove(ids: [contact[:id]], erase: true)      # also scrubs each address, as Contacts.remove
# => { data: [{ object: "contact", contact: "<uuid>", deleted: true }, ...] } — only the rows actually deleted
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
Millionsend::Domains.update(domain[:id], receiving_catch_all: true) # keep mail to addresses without an inbox (paid plans on Cloud)
Millionsend::Domains.remove(domain[:id])
```

`Domains.list` ends with the team's subdomain of the [shared domain](#the-shared-domain), after
all of your own domains; there is none when the instance has no shared domain, or while a new
team's subdomain waits for its name review. Every row carries `shared:` (absent before server
v0.14.0, so `nil` reads as false); the shared row adds `sending_mode` (`"open"`, `"reply_only"`
or `"receive_only"`) and `sending_mode_reason` (`"plan"`, `"instance"`, or `nil` when open). It
has no DNS records (`records: []`), and `update`, `verify` and `remove` raise `ForbiddenError` on
it. It only sends from an inbox's own address, so skip it when picking a sender domain:

```ruby
sender = Millionsend::Domains.list[:data].find { |d| d[:status] == "verified" && !d[:shared] }
```

### Webhooks

```ruby
hook = Millionsend::Webhooks.create(
  endpoint: "https://acme.dev/hooks/millionsend",
  events: ["email.delivered", "email.bounced", "email.complained"],
  signing_secret: "whsec_..." # optional: reuse an existing secret so the receiver keeps verifying
)
hook[:signing_secret]
Millionsend::Webhooks.get(hook[:id]) # also returns signing_secret and previous_secret_expires_at
Millionsend::Webhooks.list
Millionsend::Webhooks.update(hook[:id], events: ["email.opened"], status: "disabled")
Millionsend::Webhooks.update(hook[:id], inbox_ids: [inbox[:id]]) # inbox events for these inboxes only; nil: every inbox
Millionsend::Webhooks.remove(hook[:id])

# Rotate the signing secret (MillionSend extension) — POST /webhooks/:id/rotate
rotated = Millionsend::Webhooks.rotate(hook[:id])                                         # mints a new secret, 24h overlap
rotated = Millionsend::Webhooks.rotate(hook[:id], signing_secret: "whsec_...", overlap_hours: 0) # bring your own, no overlap
rotated[:signing_secret]              # the secret now signing deliveries
rotated[:previous_secret_expires_at]  # ISO time until which the old secret also signs, or nil
```

During the overlap window (`overlap_hours`, 0–72, default 24) every delivery carries both
signatures, so a receiver holding either verifies; `Webhooks.get` reports the window's end
as `previous_secret_expires_at` (`nil` when none is open).

Events: `email.sent`, `email.delivered`, `email.delivery_delayed`, `email.bounced`,
`email.complained`, `email.opened`, `email.clicked`, `contact.created`, `contact.updated`,
`contact.deleted`, `contact.unsubscribed`, `contact.resubscribed`, `contact.topic_opt_in`,
`contact.topic_opt_out`, `suppression.added`, `suppression.removed`, `deliverability.warning`,
`deliverability.paused`, `quota.warning`, `quota.reached`, `quota.paused`, `email.received`, and
the inbox events `inbox.created`, `inbox.updated`, `inbox.deleted`, `inbox.expired`,
`inbox.thread.created`, `inbox.thread.folder.updated`, `inbox.thread.labels.updated`,
`inbox.email.received`, `inbox.email.sent`, `inbox.email.quarantined`, `inbox.draft.created`,
`inbox.draft.updated`, `inbox.draft.sent`, `inbox.draft.deleted`. Inbox events are opt-in: an
endpoint gets them only when its `events` list names them. A shared-domain inbox deleted after
90 unused days sends `inbox.expired`, then `inbox.deleted`, and inbox events from a send in the
dashboard carry `source: "dashboard"` in their `data`.

### API keys

```ruby
key = Millionsend::ApiKeys.create(name: "ci", permission: "sending_access", domain_id: domain[:id]) # a shared: false row
key[:token] # only returned here
agent_key = Millionsend::ApiKeys.create(name: "signup-bot", permission: "full_access", inbox_id: inbox[:id])
# reads and sends for that one inbox only; list rows carry inbox_id
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

Resend's `from`, `reply_to` and `variables` template fields are passed through untouched; the
server currently answers 422 for them.

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
Millionsend::Segments.contacts(segment[:id], include: ["properties", "topics"]) # with each contact's extras, as Contacts.list
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

Subclasses: `ValidationError`, `AllRecipientsSuppressedError`, `NotFoundError`,
`MissingApiKeyError`, `InvalidApiKeyError`, `RestrictedApiKeyError`, `ForbiddenError`,
`SendingPausedError`, `BroadcastsPausedError`, `RateLimitExceededError`, `DailyQuotaExceededError`,
`InvalidIdempotentRequestError`, `ConcurrentIdempotentRequestsError`, `InternalServerError`, the
receiving and inbox errors `InboxSendPolicyError`, `InboxSendCapReachedError`,
`ApprovalRequiredError`, `EmailQuarantinedError`, `EmailBlockedError`, `TooManyWaitsError` and
`NameReviewUnavailableError`, and `ApplicationError` (the fallback for other names, such as
`plan_limit_reached`). Client-side and transport failures that never reached the API raise
`ApplicationError` with `#status_code == nil`. An unknown route raises `NotFoundError`; servers
before v0.13.0 answered it with text, which raises `ApplicationError` with status 404.

`Emails.send` and `Batch.send` raise `AllRecipientsSuppressedError` (`all_recipients_suppressed`,
422) when every `to` recipient is on the suppression list or opted out of the send's `topic_id`.

### Retries

The SDK never retries. `e.retry_after` is the response's `retry-after` header in seconds (`nil`
without one). Worth retrying once it has passed: `NameReviewUnavailableError` (60 or 300 s),
`TooManyWaitsError`, and `RateLimitExceededError` when `retry_after` is at most 60 (the
per-minute limits). Not worth retrying in the same process: `InboxSendCapReachedError`, the
daily name-review budget (a `RateLimitExceededError` whose `retry_after` runs to the next UTC
midnight), and any 403, 404, 409 or 422.

Retry a send with the same `idempotency_key` (`Emails.send`, `Batch.send`, replies, forwards and
`Drafts.send`): a retried batch gets its stored response even if a recipient was refused or
suppressed since. A held draft (`kind: "draft"`) is not a failure, so never resend it.
`Inboxes.create` takes no idempotency key: after a 503 or 429 nothing was created, but after a
timeout a resend can create a second inbox. With a chosen `username`, a 409 on the resend
usually means the first attempt worked, and `Inboxes.get(address)` finds it.

## Server versions

On a self-hosted instance, each feature needs at least this MillionSend version:

| Server  | Features |
| ------- | -------- |
| v0.8.0  | `Emails::Receiving` |
| v0.10.0 | `Inboxes` |
| v0.11.0 | `ValidationError` for recipients that can never receive mail; a retried batch replays its stored response |
| v0.12.0 | `username`; inboxes that never expire by default; sends from shared-domain inboxes; name review (`NameReviewUnavailableError`, the daily budget); `statusCode`/`name` on contacts-batch errors |
| v0.13.0 | Newest-first lists; `since` on `Codes.latest`; `quarantined` on thread items; inbox names up to 320 characters; `NotFoundError` at once for an unknown `inbox_id`; `unread` on inbox-scoped keys; JSON 404 for unknown routes |
| v0.14.0 | The shared row in `Domains.list` (`shared`, `sending_mode`, `sending_mode_reason`); `domain_id` on `Inboxes.create`; `subject` up to 998 characters |

An older server ignores options it doesn't know: before v0.14.0 `domain_id` (check the created
inbox's `email_address`), before v0.13.0 `since` (a code already used can come back), and before
v0.12.0 `username` (the address is random).

## Migrating from Resend

```diff
- require "resend"
- Resend.api_key = "re_123"
- Resend::Emails.send(from: "...", to: "...", subject: "Hi", html: "<p>hi</p>")
+ require "millionsend"
+ Millionsend.api_key  = "ms_123"
+ Millionsend.base_url = "https://mail.acme.dev" # self-hosted only
+ Millionsend::Emails.send(from: "...", to: "...", subject: "Hi", html: "<p>hi</p>")
```

Method names, nesting and payloads match; `options: { idempotency_key:, batch_validation: }`
works as in resend-ruby. Notes:

- **`update` takes the id first.** On domains, webhooks, contact properties, topics, broadcasts
  and segments it is `update(id, params)` where resend-ruby takes one hash carrying the id
  (`:id`, `:topic_id`, `:broadcast_id`, `:segment_id`); templates already match resend-ruby's
  `update(id, params)`, `Contacts.update` keeps resend's single-hash shape, and `Emails.update`
  accepts both.
- `Contacts` member methods and `Contacts::Segments` / `Contacts::Topics` accept resend-ruby's
  addressing hashes (`id:` / `email:` / `contact_id:`, `segment_id:`) as well as bare values.
  `Contacts::Topics.list` is unpaginated, so resend-ruby's `limit:`/`after:`/`before:` are not sent.
  `Suppressions::Batch` is nested as in resend-ruby.
- **No audiences** — contacts are team-global, so there is no `Audiences` resource and no
  `audience_id` params. The API's `/audiences/*` routes are a compatibility shim and are not
  part of this SDK. `Millionsend::Segments` is the dynamic-filter feature (`/segments`), not
  Resend's audiences alias.
- Not in the API (yet), so not here: broadcast recipients/clicked links, email sharing and
  metrics, contact imports, automations, logs, OAuth grants, webhook event replay.
- MillionSend extensions with no Resend counterpart: `Segments`, `Contacts::Batch`,
  `Contacts.preferences_link`, `Webhooks.rotate`, `Usage`, `Deliverability`,
  `Emails.get_insights`, `Suppressions` `origin: "unsubscribe"`, the receiving long-poll,
  `Emails::Receiving.reply`/`forward`/`remove`, and `Inboxes::Safety`, `Codes` and `Quarantine`.

## License

MIT
