# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class RegisterMergeSnapshot < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: [ "agent" ])
          required(:id).filled(:string)
        end
        required(:merge_snapshot_id).filled(:string)
        required(:repository_id).filled(:string)
        required(:target_branch).filled(:string)
        required(:target_base_commit_oid).filled(:string)
        required(:ordered_candidates).array(:hash) do
          required(:candidate_id).filled(:string)
          required(:head_commit_oid).filled(:string)
        end
        required(:merge_commit_oid).filled(:string)
        required(:producer).hash do
          required(:name).filled(:string)
          required(:version).filled(:string)
        end
        required(:run_id).filled(:string)
        required(:produced_at).filled(:string)
      end

      rule(:command_id, :merge_snapshot_id, :run_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:id))
          key([ :actor, :id ]).failure("must be a valid identifier")
        end
      end

      rule(:repository_id) do
        key.failure("must be a valid repository identifier") unless Types::REPOSITORY_ID_PATTERN.match?(value)
      end

      rule(:target_branch) do
        key.failure("must be a canonical Git branch ref") unless valid_branch?(value)
      end

      rule(:ordered_candidates) do
        unless (1..Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES).cover?(value.length)
          key.failure("must contain between 1 and 32 entries")
        end
        candidate_ids = value.map { _1.fetch(:candidate_id) }
        heads = value.map { _1.fetch(:head_commit_oid) }
        key.failure("must not contain duplicate Candidate IDs") unless candidate_ids.uniq.length == candidate_ids.length
        key.failure("must not contain duplicate Candidate heads") unless heads.uniq.length == heads.length

        value.each_with_index do |candidate, index|
          unless Types::IDENTIFIER_PATTERN.match?(candidate.fetch(:candidate_id))
            key([ :ordered_candidates, index, :candidate_id ]).failure("must be a valid identifier")
          end
          unless Types::GIT_OID_PATTERN.match?(candidate.fetch(:head_commit_oid))
            key([ :ordered_candidates, index, :head_commit_oid ]).failure(
              "must be a lowercase SHA-1 or SHA-256 OID"
            )
          end
        end
      end

      rule(:target_base_commit_oid, :merge_commit_oid, :ordered_candidates) do
        base = values[:target_base_commit_oid]
        snapshot = values[:merge_commit_oid]
        next unless base && snapshot

        unless Types::GIT_OID_PATTERN.match?(base)
          key(:target_base_commit_oid).failure("must be a lowercase SHA-1 or SHA-256 OID")
        end
        unless Types::GIT_OID_PATTERN.match?(snapshot)
          key(:merge_commit_oid).failure("must be a lowercase SHA-1 or SHA-256 OID")
        end
        next unless Types::GIT_OID_PATTERN.match?(base) && Types::GIT_OID_PATTERN.match?(snapshot)

        key(:merge_commit_oid).failure("must differ from target_base_commit_oid") if snapshot == base
        oids = [ snapshot, *values[:ordered_candidates].map { _1.fetch(:head_commit_oid) } ]
        unless oids.all? { _1.length == base.length }
          key.failure("all Git OIDs must use one object format")
        end
      end

      rule(:producer) do
        %i[name version].each do |field|
          content = value.fetch(field)
          next if content.valid_encoding? && content.encoding == Encoding::UTF_8 && content.length.between?(1, 100)

          key([ :producer, field ]).failure("must contain 1 to 100 UTF-8 characters")
        end
      end

      rule(:produced_at) do
        key.failure("must be a UTC timestamp with microseconds") unless Types::TIMESTAMP_PATTERN.match?(value)
      end

      private

      def valid_branch?(value)
        value.valid_encoding? && value.encoding == Encoding::UTF_8 &&
          value.bytesize.between?(1, 255) &&
          !/[\u0000-\u0020\u007f~^:?*\[\\]/.match?(value) &&
          !value.include?("..") && !value.include?("@{") &&
          !value.start_with?("/", ".") && !value.end_with?("/", ".") &&
          value.split("/", -1).none? { _1.empty? || _1.end_with?(".lock") }
      end
    end
  end
end
