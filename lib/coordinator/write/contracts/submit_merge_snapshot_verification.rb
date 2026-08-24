# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class SubmitMergeSnapshotVerification < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: [ "agent" ])
          required(:id).filled(:string)
        end
        required(:merge_snapshot_id).filled(:string)
        required(:binding).hash do
          required(:snapshot_event).hash do
            required(:event_id).filled(:string)
            required(:type).filled(:string, eql?: "MergeSnapshotRegistered")
            required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
            required(:stream_name).filled(:string, eql?: "MergeSnapshot")
            required(:stream_id).filled(:string)
            required(:stream_revision).filled(:integer, eql?: 0)
          end
          required(:snapshot_digest).filled(:string)
          required(:repository_id).filled(:string)
          required(:target_branch).filled(:string)
          required(:object_format).filled(:string, included_in?: Types::GIT_OBJECT_FORMATS)
          required(:target_base_commit_oid).filled(:string)
          required(:ordered_candidates).array(:hash) do
            required(:candidate_id).filled(:string)
            required(:head_commit_oid).filled(:string)
          end
          required(:merge_commit_oid).filled(:string)
        end
        required(:assessment).hash do
          required(:evidence_kind).filled(
            :string,
            included_in?: Types::MERGE_SNAPSHOT_VERIFICATION_EVIDENCE_KINDS
          )
          required(:producer).hash do
            required(:name).filled(:string)
            required(:version).filled(:string)
          end
          required(:run_id).filled(:string)
          required(:test_suite_digest).filled(:string)
          required(:environment_digest).filled(:string)
          required(:result_digest).filled(:string)
          required(:conclusion).filled(:string, included_in?: Types::VERIFICATION_EVIDENCE_CONCLUSIONS)
          required(:findings).array(:hash) do
            required(:code).filled(:string)
            required(:severity).filled(
              :string,
              included_in?: Types::VERIFICATION_EVIDENCE_FINDING_SEVERITIES
            )
            required(:summary).filled(:string)
            optional(:path).maybe(:string)
          end
          required(:produced_at).filled(:string)
        end
      end

      rule(:command_id, :merge_snapshot_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:id))
      end

      rule(:binding, :merge_snapshot_id) do
        binding = values[:binding]
        snapshot_id = values[:merge_snapshot_id]
        validate_binding(key, binding, snapshot_id) if binding && snapshot_id
      end

      rule(:assessment) do
        validate_assessment(key, value)
      end

      private

      def validate_binding(key, binding, merge_snapshot_id)
        reference = binding.fetch(:snapshot_event)
        key.failure("snapshot_event.event_id must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(reference.fetch(:event_id))
        unless reference.fetch(:stream_id) == merge_snapshot_id
          key.failure("snapshot_event must identify the requested merge snapshot")
        end
        key.failure("snapshot_digest must be a SHA-256 digest") unless Types::SHA256_DIGEST_PATTERN.match?(binding.fetch(:snapshot_digest))
        unless Types::REPOSITORY_ID_PATTERN.match?(binding.fetch(:repository_id))
          key.failure("repository_id must be a valid repository identifier")
        end
        key.failure("target_branch must be a canonical Git branch ref") unless valid_branch?(binding.fetch(:target_branch))
        candidates = binding.fetch(:ordered_candidates)
        unless (1..Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES).cover?(candidates.length)
          key.failure("ordered_candidates must contain between 1 and 32 entries")
        end
        ids = candidates.map { _1.fetch(:candidate_id) }
        heads = candidates.map { _1.fetch(:head_commit_oid) }
        key.failure("ordered_candidates must not repeat candidate IDs") unless ids.uniq.length == ids.length
        key.failure("ordered_candidates must not repeat candidate heads") unless heads.uniq.length == heads.length
        candidates.each do |candidate|
          key.failure("candidate_id must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(candidate.fetch(:candidate_id))
        end
        oids = [
          binding.fetch(:target_base_commit_oid),
          binding.fetch(:merge_commit_oid),
          *heads
        ]
        key.failure("all Git OIDs must be lowercase SHA-1 or SHA-256 OIDs") unless oids.all? { Types::GIT_OID_PATTERN.match?(_1) }
        expected_length = binding.fetch(:object_format) == "sha1" ? 40 : 64
        key.failure("all Git OIDs must match object_format") unless oids.all? { _1.length == expected_length }
      end

      def validate_assessment(key, assessment)
        producer = assessment.fetch(:producer)
        validate_length(key, "producer.name", producer.fetch(:name), 100)
        validate_length(key, "producer.version", producer.fetch(:version), 100)
        key.failure("run_id must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(assessment.fetch(:run_id))
        %i[test_suite_digest environment_digest result_digest].each do |field|
          key.failure("#{field} must be a SHA-256 digest") unless Types::SHA256_DIGEST_PATTERN.match?(assessment.fetch(field))
        end
        key.failure("produced_at must be a UTC timestamp with microseconds") unless Types::TIMESTAMP_PATTERN.match?(assessment.fetch(:produced_at))
        findings = assessment.fetch(:findings)
        key.failure("findings must contain at most 32 entries") if findings.length > 32
        findings.each_with_index do |finding, index|
          validate_length(key, "findings[#{index}].code", finding.fetch(:code), 100)
          validate_length(key, "findings[#{index}].summary", finding.fetch(:summary), 2_000)
          path = finding[:path]
          key.failure("findings[#{index}].path must be a valid resource path") if path && !Types::RESOURCE_PATH_PATTERN.match?(path)
        end
        conclusion = assessment.fetch(:conclusion)
        key.failure("findings must explain a non-passed conclusion") if conclusion != "passed" && findings.empty?
        if conclusion == "passed" && findings.any? { %w[error critical].include?(_1.fetch(:severity)) }
          key.failure("passed evidence must not contain error or critical findings")
        end
      end

      def validate_length(key, name, value, maximum)
        return if value.valid_encoding? && value.encoding == Encoding::UTF_8 && value.length.between?(1, maximum)

        key.failure("#{name} must contain 1 to #{maximum} UTF-8 characters")
      end

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
