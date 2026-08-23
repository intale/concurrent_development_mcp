# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class SubmitCandidateImpactSurface < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: [ "agent" ])
          required(:id).filled(:string)
        end
        required(:candidate_id).filled(:string)
        required(:repository_id).filled(:string)
        required(:head_commit_oid).filled(:string)
        required(:manifest_digest).filled(:string)
        optional(:build_context_digest).maybe(:string)
        required(:analyzer_version).filled(:string)
        required(:surface).hash do
          required(:produces).array(:hash) do
            required(:impact_key).filled(:string)
            optional(:before).maybe(:string)
            required(:after).filled(:string)
          end
          required(:consumes).array(:hash) do
            required(:impact_key).filled(:string)
            required(:value).filled(:string)
          end
          required(:may_affect).array(:hash) do
            required(:impact_key).filled(:string)
          end
          required(:assumes).array(:hash) do
            required(:impact_key).filled(:string)
            required(:predicate).filled(:string)
          end
        end
      end

      rule(:command_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:candidate_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:id))
      end

      rule(:repository_id) do
        key.failure("must be a valid repository identifier") unless Types::REPOSITORY_ID_PATTERN.match?(value)
      end

      rule(:head_commit_oid) do
        key.failure("must be a lowercase SHA-1 or SHA-256 OID") unless Types::GIT_OID_PATTERN.match?(value)
      end

      rule(:manifest_digest) do
        key.failure("must be a SHA-256 digest") unless Types::SHA256_DIGEST_PATTERN.match?(value)
      end

      rule(:build_context_digest) do
        next if value.nil? || Types::SHA256_DIGEST_PATTERN.match?(value)

        key.failure("must be a SHA-256 digest")
      end

      rule(:analyzer_version) do
        key.failure("must contain 1 to 100 UTF-8 bytes") unless bounded_utf8?(value, 100)
      end

      rule(:surface) do
        total = Types::CANDIDATE_IMPACT_SURFACE_DIRECTIONS.sum { value.fetch(_1.to_sym).length }
        key.failure("must contain between 1 and 128 total entries") unless (1..128).cover?(total)

        Types::CANDIDATE_IMPACT_SURFACE_DIRECTIONS.each do |direction|
          entries = value.fetch(direction.to_sym)
          key([ :surface, direction.to_sym ]).failure("must contain at most 64 entries") if entries.length > 64
          keys = entries.map { _1.fetch(:impact_key) }
          key([ :surface, direction.to_sym ]).failure("must not repeat an impact key") unless keys.uniq.length == keys.length
          entries.each_with_index do |entry, index|
            impact_key = entry.fetch(:impact_key)
            unless impact_key.bytesize.between?(3, 200) &&
                   Types::CANDIDATE_IMPACT_KEY_PATTERN.match?(impact_key)
              key([ :surface, direction.to_sym, index, :impact_key ]).failure(
                "must be a normalized impact key"
              )
            end

            (entry.keys - [ :impact_key ]).each do |name|
              content = entry[name]
              next if content.nil? || bounded_utf8?(content, 500)

              key([ :surface, direction.to_sym, index, name ]).failure(
                "must contain 1 to 500 UTF-8 bytes"
              )
            end
          end
        end
      end

      private

      def bounded_utf8?(value, maximum)
        value.encoding == Encoding::UTF_8 && value.valid_encoding? &&
          value.bytesize.between?(1, maximum) && !value.include?("\u0000")
      end
    end
  end
end
