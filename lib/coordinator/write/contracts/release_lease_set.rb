# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class ReleaseLeaseSet < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: [ "agent" ])
          required(:id).filled(:string)
        end
        required(:change_set_id).filled(:string)
        required(:work_item_id).filled(:string)
        required(:attempt_id).filled(:string)
        required(:lease_set_id).filled(:string)
        required(:leases).array(:hash) do
          required(:resource_key_hash).filled(:string)
          required(:lease_id).filled(:string)
          required(:fencing_token).filled(:integer)
        end
      end

      rule(:command_id, :change_set_id, :work_item_id, :attempt_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        actor_id = value[:id]
        next unless actor_id.is_a?(String)

        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(actor_id)
      end

      rule(:lease_set_id) do
        key.failure("must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:leases) do
        unless (1..32).cover?(value.length)
          key.failure("must contain between 1 and 32 entries")
          next
        end

        value.each_with_index do |reference, index|
          hash = reference[:resource_key_hash]
          lease_id = reference[:lease_id]
          token = reference[:fencing_token]
          unless hash.is_a?(String) && Types::SHA256_DIGEST_PATTERN.match?(hash)
            key([ :leases, index, :resource_key_hash ]).failure("must be a SHA-256 resource digest")
          end
          unless lease_id.is_a?(String) && Types::UUID_V7_PATTERN.match?(lease_id)
            key([ :leases, index, :lease_id ]).failure("must be a UUIDv7")
          end
          unless token.is_a?(Integer) && token >= 1
            key([ :leases, index, :fencing_token ]).failure("must be at least 1")
          end
        end

        hashes = value.filter_map { _1[:resource_key_hash] }
        lease_ids = value.filter_map { _1[:lease_id] }
        key.failure("must not repeat a resource identity") unless hashes.uniq.length == hashes.length
        key.failure("must not repeat a lease ID") unless lease_ids.uniq.length == lease_ids.length
      end
    end
  end
end
