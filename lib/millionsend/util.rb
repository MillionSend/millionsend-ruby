# frozen_string_literal: true

require "uri"

module Millionsend
  # Small shared helpers used across the resource modules.
  module Util
    module_function

    # Percent-encode a single URL path segment (contact ids and emails, which
    # can contain "@" and "+"). encode_www_form_component is form encoding, so
    # it maps space to "+" — wrong inside a path segment, where servers decode
    # "+" literally. It already turned real plus signs into %2B, so every
    # remaining "+" is a space and can safely become %20.
    def encode(value)
      URI.encode_www_form_component(value.to_s).gsub("+", "%20")
    end

    # The keyset pagination params every list endpoint accepts. nil values are
    # dropped when the query string is built.
    def list_query(options)
      options ||= {}
      { limit: options[:limit], after: options[:after], before: options[:before] }
    end
  end
end
