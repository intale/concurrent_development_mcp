# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class ReserveWriteSet < Dry::Validation::Contract
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
        required(:repository_id).filled(:string)
        required(:base_commit_oid).value(:string)
        required(:resources).array(:hash) do
          required(:kind).filled(:string)
          required(:path).value(:string)
          optional(:base_blob_oid).maybe(:string)
        end
        required(:lease_duration_seconds).value(:integer)
      end

      rule(:command_id, :change_set_id, :work_item_id, :attempt_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        actor_id = value[:id]
        next unless actor_id.is_a?(String)

        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(actor_id)
      end

      rule(:repository_id) do
        key.failure("must be a valid repository identifier") unless Types::REPOSITORY_ID_PATTERN.match?(value)
      end

      rule(:resources) do
        key.failure("must contain between 1 and 32 entries") unless (1..32).cover?(value.length)
      end

      rule(:base_commit_oid, :resources) do
        base_commit_oid = values[:base_commit_oid]
        next unless base_commit_oid.is_a?(String) && Types::GIT_OID_PATTERN.match?(base_commit_oid)

        values[:resources].each_with_index do |resource, index|
          base_blob_oid = resource[:base_blob_oid]
          next unless base_blob_oid.is_a?(String) && Types::GIT_OID_PATTERN.match?(base_blob_oid)
          next if base_blob_oid.length == base_commit_oid.length

          key([ :resources, index, :base_blob_oid ]).failure("must use the repository base object format")
        end
      end

      rule(:lease_duration_seconds) do
        key.failure("must be between 30 and 3600 seconds") unless (30..3_600).cover?(value)
      end
    end
  end
end
