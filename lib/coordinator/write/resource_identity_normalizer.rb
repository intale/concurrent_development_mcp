# frozen_string_literal: true

module Coordinator::Write
  class ResourceIdentityNormalizer
    include Dry::Monads[:result]

    def initialize(
      contract: Contracts::ResourceIdentity.new,
      marker_codec: Coordinator::Shared::ResourceMarkerCodec.new
    )
      @contract = contract
      @marker_codec = marker_codec
    end

    def call(repository_id:, kind:, path:)
      validation = @contract.call(repository_id:, kind:, path:)
      return Failure(invalid_identity(validation.errors.to_h)) unless validation.success?

      attributes = validation.to_h
      normalized_path = attributes.fetch(:path).unicode_normalize(:nfc)

      Success(
        ResourceIdentityV1.new(
          repository_id: attributes.fetch(:repository_id),
          kind: attributes.fetch(:kind),
          normalized_path:,
          identity_marker: @marker_codec.identity(
            repository_id: attributes.fetch(:repository_id),
            kind: attributes.fetch(:kind),
            normalized_path:
          ),
          current_path_marker: @marker_codec.current_path(
            repository_id: attributes.fetch(:repository_id),
            normalized_path:
          )
        )
      )
    end

    private

    def invalid_identity(errors)
      OutcomeError.new(
        code: :resource_identity_invalid,
        message: "Resource identity is invalid",
        details: { errors: }
      )
    end
  end
end
