# frozen_string_literal: true

# Opt-in end-to-end smoke test against a real MillionSend instance. The whole
# group only runs when MILLIONSEND_API_KEY is set; otherwise it is skipped. Set
# MILLIONSEND_BASE_URL too if you are not on http://localhost:3001. It exercises
# the audience + contact lifecycle, which needs no verified sender domain.
#
#   MILLIONSEND_API_KEY=ms_... MILLIONSEND_BASE_URL=http://localhost:3001 \
#     bundle exec rspec spec/e2e_spec.rb
RSpec.describe "e2e: audiences + contacts lifecycle", :e2e, if: ENV["MILLIONSEND_API_KEY"] do
  before(:all) do
    WebMock.allow_net_connect!
    Millionsend.api_key = ENV["MILLIONSEND_API_KEY"]
    Millionsend.base_url = ENV["MILLIONSEND_BASE_URL"]
  end

  after(:all) do
    WebMock.disable_net_connect!
  end

  it "creates, reads, updates and deletes a contact in an audience" do
    audience = Millionsend::Audiences.create(name: "sdk-e2e-#{Time.now.to_i}")
    audience_id = audience[:id]
    expect(audience_id).not_to be_nil

    begin
      email = "sdk-e2e-#{Time.now.to_i}@example.com"
      Millionsend::Contacts.create(audience_id: audience_id, email: email, first_name: "Ada")

      fetched = Millionsend::Contacts.get(email, audience_id: audience_id)
      expect(fetched[:email]).to eq(email)
      expect(fetched[:first_name]).to eq("Ada")

      Millionsend::Contacts.update(audience_id: audience_id, email: email, unsubscribed: true)

      removed = Millionsend::Contacts.remove(email, audience_id: audience_id)
      expect(removed[:deleted]).to eq(true)
    ensure
      Millionsend::Audiences.remove(audience_id)
    end
  end

  it "raises not_found for a missing contact" do
    expect { Millionsend::Contacts.get("does-not-exist@example.com") }
      .to raise_error(Millionsend::NotFoundError)
  end
end
