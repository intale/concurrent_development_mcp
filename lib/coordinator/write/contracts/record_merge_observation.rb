# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class RecordMergeObservation < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: [ "agent" ])
          required(:id).filled(:string)
        end
        required(:merge_snapshot_id).filled(:string)
        required(:authorization_event).hash do
          required(:event_id).filled(:string)
          required(:type).filled(:string, eql?: "MergeAuthorizationGranted")
          required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
          required(:stream_name).filled(:string, eql?: "MergeAuthorization")
          required(:stream_id).filled(:string)
          required(:stream_revision).filled(:integer, eql?: 0)
        end
        required(:authorization_decision_digest).filled(:string)
        required(:repository_id).filled(:string)
        required(:target_branch).filled(:string)
        required(:object_format).filled(:string, included_in?: Types::GIT_OBJECT_FORMATS)
        required(:target_before_commit_oid).filled(:string)
        required(:target_after_commit_oid).filled(:string)
        required(:observer).hash do
          required(:name).filled(:string)
          required(:version).filled(:string)
        end
        required(:run_id).filled(:string)
        required(:observed_at).filled(:string)
      end

      rule(:command_id, :merge_snapshot_id, :actor, :authorization_event, :run_id) do
        identifiers = [
          values[:command_id], values[:merge_snapshot_id], values.dig(:actor, :id),
          values.dig(:authorization_event, :stream_id), values[:run_id]
        ].compact
        key.failure("identifiers must use the canonical format") unless identifiers.all? { Types::IDENTIFIER_PATTERN.match?(_1) }
        event_id = values.dig(:authorization_event, :event_id)
        key.failure("authorization event ID must be a UUIDv7") if event_id && !Types::UUID_V7_PATTERN.match?(event_id)
      end

      rule(:authorization_decision_digest) do
        key.failure("must be a SHA-256 digest") unless Types::SHA256_DIGEST_PATTERN.match?(value)
      end

      rule(:repository_id, :target_branch, :object_format, :target_before_commit_oid, :target_after_commit_oid) do
        key.failure("repository_id must be canonical") unless Types::REPOSITORY_ID_PATTERN.match?(values[:repository_id])
        key.failure("target_branch must be a canonical Git branch ref") unless valid_branch?(values[:target_branch])
        oids = [ values[:target_before_commit_oid], values[:target_after_commit_oid] ]
        expected_length = values[:object_format] == "sha1" ? 40 : 64
        unless oids.all? { Types::GIT_OID_PATTERN.match?(_1) && _1.length == expected_length }
          key.failure("Git OIDs must be lowercase and match object_format")
        end
      end

      rule(:observer) do
        name = value.fetch(:name)
        version = value.fetch(:version)
        key.failure("name must contain at most 100 characters") if name.length > 100
        key.failure("version must contain at most 100 characters") if version.length > 100
      end

      rule(:observed_at) do
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
