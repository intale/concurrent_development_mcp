# frozen_string_literal: true

module Coordinator::Read::Search
  class CursorCodec
    class InvalidCursor < ArgumentError; end

    class PayloadContract < Dry::Validation::Contract
      config.validate_keys = true

      json do
        required(:version).filled(:integer, eql?: 1)
        required(:fingerprint).filled(:string, format?: /\A[0-9a-f]{64}\z/)
        required(:updated_at).filled(:string, format?: Coordinator::Read::Types::TIMESTAMP_PATTERN)
        required(:entity_type).filled(:string, included_in?: FieldCatalog::ENTITY_TYPES)
        required(:document_id).filled(:string, max_size?: 2048)
      end
    end

    def initialize(secret:, contract: PayloadContract.new, canonical_json: Coordinator::Shared::CanonicalJson.new)
      @secret = secret
      @contract = contract
      @canonical_json = canonical_json
    end

    def fingerprint(fields:, filters:)
      document = { fields: fields.map(&:to_h), filters: filters.to_h }
      OpenSSL::Digest::SHA256.hexdigest(@canonical_json.encode(document))
    end

    def encode(boundary:, fingerprint:)
      payload = Base64.urlsafe_encode64(@canonical_json.encode(
        version: 1, fingerprint:, **boundary.to_h
      ), padding: false)
      "#{payload}.#{signature(payload)}"
    end

    def decode(cursor, fingerprint:)
      raise InvalidCursor, "Search cursor format is invalid" unless /\A[A-Za-z0-9_-]+\.[0-9a-f]{64}\z/.match?(cursor)

      payload, supplied_signature = cursor.split(".", -1)
      expected = signature(payload || "")
      unless supplied_signature && supplied_signature.bytesize == expected.bytesize &&
             OpenSSL.fixed_length_secure_compare(supplied_signature, expected)
        raise InvalidCursor, "Search cursor integrity check failed"
      end
      decoded = Base64.urlsafe_decode64(payload)
      raise InvalidCursor, "Search cursor encoding is invalid" unless Base64.urlsafe_encode64(decoded, padding: false) == payload

      document = @contract.call(JSON.parse(decoded))
      raise InvalidCursor, "Search cursor payload is invalid" if document.failure?

      values = document.to_h
      raise InvalidCursor, "Search cursor belongs to a different query" unless values.fetch(:fingerprint) == fingerprint

      timestamp = values.fetch(:updated_at)
      raise InvalidCursor, "Search cursor timestamp is invalid" unless Time.iso8601(timestamp).utc.iso8601(6) == timestamp

      CursorBoundary.new(values.slice(:updated_at, :entity_type, :document_id))
    rescue JSON::ParserError, ArgumentError => error
      raise InvalidCursor, error.message
    end

    private

    def signature(payload)
      OpenSSL::HMAC.hexdigest("SHA256", @secret, "development-search/v1:#{payload}")
    end
  end
end
