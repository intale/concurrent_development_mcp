# frozen_string_literal: true

module Coordinator::Read::Web
  class ProjectReference
    SCHEMA_VERSION = "project-reference/v1"

    class InvalidReference < ArgumentError; end

    class PayloadContract < Dry::Validation::Contract
      config.validate_keys = true

      json do
        required(:schema).filled(:string, eql?: SCHEMA_VERSION)
        required(:scope).filled(:string)
      end
    end

    def initialize(
      payload_contract: PayloadContract.new,
      scope_contract: Coordinator::Read::Contracts::RepositoryList.new,
      canonical_json: Coordinator::Shared::CanonicalJson.new
    )
      @payload_contract = payload_contract
      @scope_contract = scope_contract
      @canonical_json = canonical_json
    end

    def encode(scope:)
      validate_scope!(scope)
      document = @canonical_json.encode("schema" => SCHEMA_VERSION, "scope" => scope)

      Base64.urlsafe_encode64(document, padding: false)
    end

    def decode(reference)
      document = JSON.parse(Base64.urlsafe_decode64(reference))
      payload = @payload_contract.call(document)
      raise InvalidReference, "project reference is invalid" if payload.failure?

      scope = payload.to_h.fetch(:scope)
      validate_scope!(scope)
      raise InvalidReference, "project reference is invalid" unless encode(scope:) == reference

      scope
    rescue JSON::ParserError, ArgumentError, TypeError, KeyError, Coordinator::Shared::CanonicalJson::Error
      raise InvalidReference, "project reference is invalid"
    end

    private

    def validate_scope!(scope)
      result = @scope_contract.call(scope:)
      raise InvalidReference, "project scope is invalid" if result.failure?
    end
  end
end
