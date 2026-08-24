# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class RequestMergeAuthorization < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: [ "agent" ])
          required(:id).filled(:string)
        end
        required(:merge_snapshot_id).filled(:string)
        required(:snapshot_binding).hash do
          required(:registration_event).hash do
            required(:event_id).filled(:string)
            required(:type).filled(:string, eql?: "MergeSnapshotRegistered")
            required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
            required(:stream_name).filled(:string, eql?: "MergeSnapshot")
            required(:stream_id).filled(:string)
            required(:stream_revision).filled(:integer, eql?: 0)
          end
          required(:snapshot_digest).filled(:string)
          required(:verification_event).hash do
            required(:event_id).filled(:string)
            required(:type).filled(:string, eql?: "MergeSnapshotVerified")
            required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
            required(:stream_name).filled(:string, eql?: "MergeSnapshot")
            required(:stream_id).filled(:string)
            required(:stream_revision).filled(:integer, gteq?: 2)
          end
          required(:verification_digest).filled(:string)
        end
        required(:target_base_observation).hash do
          required(:repository_id).filled(:string)
          required(:target_branch).filled(:string)
          required(:object_format).filled(:string, included_in?: Types::GIT_OBJECT_FORMATS)
          required(:commit_oid).filled(:string)
          required(:observer).hash do
            required(:name).filled(:string)
            required(:version).filled(:string)
          end
          required(:run_id).filled(:string)
          required(:observed_at).filled(:string)
        end
        required(:expected_impact_policy).maybe do
          hash do
            required(:partition_event).hash do
              required(:event_id).filled(:string)
              required(:type).filled(:string, eql?: "DecisionPartitionAdvanced")
              required(:stream_context).filled(:string, eql?: "HumanGuidance")
              required(:stream_name).filled(:string, eql?: "DecisionPartition")
              required(:stream_id).filled(:string)
              required(:stream_revision).filled(:integer, gteq?: 0)
            end
            required(:head).hash do
              required(:decision_id).filled(:string)
              required(:decision_revision).filled(:integer, gteq?: 1)
              required(:event).hash do
                required(:event_id).filled(:string)
                required(:type).filled(
                  :string,
                  included_in?: %w[DecisionActivated DecisionDefinitionCorrected]
                )
                required(:stream_context).filled(:string, eql?: "HumanGuidance")
                required(:stream_name).filled(:string, eql?: "Decision")
                required(:stream_id).filled(:string)
                required(:stream_revision).filled(:integer, gteq?: 1)
              end
            end
            required(:definition_digest).filled(:string)
          end
        end
      end

      rule(:command_id, :merge_snapshot_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:id))
      end

      rule(:snapshot_binding, :merge_snapshot_id) do
        validate_snapshot_binding(key, values[:snapshot_binding], values[:merge_snapshot_id])
      end

      rule(:target_base_observation) do
        validate_target_base(key, value)
      end

      rule(:expected_impact_policy) do
        validate_expected_policy(key, value) if value
      end

      private

      def validate_snapshot_binding(key, binding, merge_snapshot_id)
        %i[registration_event verification_event].each do |field|
          reference = binding.fetch(field)
          key.failure("#{field}.event_id must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(reference.fetch(:event_id))
          key.failure("#{field} must identify the requested snapshot") unless reference.fetch(:stream_id) == merge_snapshot_id
        end
        %i[snapshot_digest verification_digest].each do |field|
          key.failure("#{field} must be a SHA-256 digest") unless Types::SHA256_DIGEST_PATTERN.match?(binding.fetch(field))
        end
      end

      def validate_target_base(key, observation)
        unless Types::REPOSITORY_ID_PATTERN.match?(observation.fetch(:repository_id))
          key.failure("repository_id must be a valid repository identifier")
        end
        key.failure("target_branch must be a canonical Git branch ref") unless valid_branch?(observation.fetch(:target_branch))
        oid = observation.fetch(:commit_oid)
        expected_length = observation.fetch(:object_format) == "sha1" ? 40 : 64
        unless Types::GIT_OID_PATTERN.match?(oid) && oid.length == expected_length
          key.failure("commit_oid must match object_format")
        end
        observer = observation.fetch(:observer)
        validate_length(key, "observer.name", observer.fetch(:name), 100)
        validate_length(key, "observer.version", observer.fetch(:version), 100)
        key.failure("run_id must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(observation.fetch(:run_id))
        unless Types::TIMESTAMP_PATTERN.match?(observation.fetch(:observed_at))
          key.failure("observed_at must be a UTC timestamp with microseconds")
        end
      end

      def validate_expected_policy(key, policy)
        partition = policy.fetch(:partition_event)
        head = policy.fetch(:head)
        event = head.fetch(:event)
        key.failure("partition_event.event_id must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(partition.fetch(:event_id))
        key.failure("head.event.event_id must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(event.fetch(:event_id))
        key.failure("head.decision_id must be valid") unless Types::IDENTIFIER_PATTERN.match?(head.fetch(:decision_id))
        unless event.fetch(:stream_id) == head.fetch(:decision_id) &&
               event.fetch(:stream_revision) == head.fetch(:decision_revision)
          key.failure("head event must identify the exact Decision revision")
        end
        unless Types::SHA256_DIGEST_PATTERN.match?(policy.fetch(:definition_digest))
          key.failure("definition_digest must be a SHA-256 digest")
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
