# frozen_string_literal: true

require "millionsend/version"
require "millionsend/util"
require "millionsend/error"
require "millionsend/request"
require "millionsend/emails"
require "millionsend/batch"
require "millionsend/contacts"
require "millionsend/topics"
require "millionsend/broadcasts"
require "millionsend/segments"

# Ruby client for the MillionSend HTTP API. Configure once, then call the
# resource modules:
#
#   Millionsend.api_key  = "ms_..."
#   Millionsend.base_url = "https://mail.acme.dev"
#   Millionsend::Emails.send(from: "onboarding@acme.dev", to: "you@example.com",
#                            subject: "Hi", html: "<strong>it works</strong>")
#
# api_key falls back to the MILLIONSEND_API_KEY env var; base_url to
# MILLIONSEND_BASE_URL and then http://localhost:3001 (MillionSend is
# self-hosted, so there is no cloud default). Plain http is only accepted for
# loopback hosts unless allow_insecure_http is set, since the API key travels
# as a bearer header. Every call returns a symbol-keyed Hash on success and
# raises a Millionsend::Error on any non-2xx response.
module Millionsend
  DEFAULT_BASE_URL = "http://localhost:3001"
  USER_AGENT = "millionsend-ruby/#{VERSION}"

  class << self
    attr_writer :api_key, :base_url
    attr_accessor :allow_insecure_http

    def api_key
      @api_key || ENV["MILLIONSEND_API_KEY"]
    end

    def base_url
      @base_url || ENV["MILLIONSEND_BASE_URL"] || DEFAULT_BASE_URL
    end
  end
end
