# frozen_string_literal: true

module Coordinator::Web::Graphql
  class DashboardCursor
    PREFIX = "coordination-dashboard:v1"
    KINDS = %w[change-sets work-items dependencies].freeze

    def self.encode(kind, offset)
      Base64.urlsafe_encode64("#{PREFIX}:#{kind}:#{offset}", padding: false)
    end

    def self.decode(cursor, kind)
      return 0 unless cursor

      prefix, version, decoded_kind, offset = Base64.urlsafe_decode64(cursor).split(":", 4)
      valid_prefix = [ prefix, version ].join(":") == PREFIX
      valid = valid_prefix && KINDS.include?(kind) && decoded_kind == kind && /\A\d+\z/.match?(offset.to_s)
      raise InvalidCursor, "#{kind} cursor is invalid" unless valid

      Integer(offset, 10)
    rescue ArgumentError
      raise InvalidCursor, "#{kind} cursor is invalid"
    end
  end
end
