# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class PrepareReleaseSet < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: [ "agent" ])
          required(:id).filled(:string)
        end
        required(:release_set_id).filled(:string)
        required(:ordered_members).array(:hash, min_size?: Types::RELEASE_SET_MINIMUM_MEMBERS, max_size?: Types::RELEASE_SET_MAXIMUM_MEMBERS) do
          required(:repository_id).filled(:string)
          required(:target_branch).filled(:string)
          required(:object_format).filled(:string, included_in?: Types::GIT_OBJECT_FORMATS)
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
          required(:authorization_event).hash do
            required(:event_id).filled(:string)
            required(:type).filled(:string, eql?: "MergeAuthorizationGranted")
            required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
            required(:stream_name).filled(:string, eql?: "MergeAuthorization")
            required(:stream_id).filled(:string)
            required(:stream_revision).filled(:integer, eql?: 0)
          end
          required(:authorization_decision_digest).filled(:string)
        end
      end

      rule(:command_id, :release_set_id, :actor) do
        identifiers = [ values[:command_id], values[:release_set_id], values.dig(:actor, :id) ].compact
        key.failure("identifiers must use the canonical format") unless identifiers.all? { Types::IDENTIFIER_PATTERN.match?(_1) }
      end

      rule(:ordered_members) do
        validate_members(key, value)
      end

      private

      def validate_members(key, members)
        repositories = members.map { _1.fetch(:repository_id) }
        snapshots = members.map { _1.fetch(:merge_snapshot_id) }
        authorizations = members.map { _1.dig(:authorization_event, :event_id) }
        key.failure("repository_id values must be unique") unless repositories.uniq.length == repositories.length
        key.failure("merge_snapshot_id values must be unique") unless snapshots.uniq.length == snapshots.length
        key.failure("authorization events must be unique") unless authorizations.uniq.length == authorizations.length

        members.each_with_index do |member, index|
          validate_member(key, member, index: index + 1)
        end
      end

      def validate_member(key, member, index:)
        key.failure("member #{index} repository_id must be canonical") unless Types::REPOSITORY_ID_PATTERN.match?(member.fetch(:repository_id))
        key.failure("member #{index} target_branch must be canonical") unless valid_branch?(member.fetch(:target_branch))
        key.failure("member #{index} merge_snapshot_id must be valid") unless Types::IDENTIFIER_PATTERN.match?(member.fetch(:merge_snapshot_id))

        binding = member.fetch(:snapshot_binding)
        references = [ binding.fetch(:registration_event), binding.fetch(:verification_event) ]
        references.each do |reference|
          key.failure("member #{index} event_id must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(reference.fetch(:event_id))
          key.failure("member #{index} snapshot event must identify merge_snapshot_id") unless reference.fetch(:stream_id) == member.fetch(:merge_snapshot_id)
        end
        key.failure("member #{index} authorization event_id must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(member.dig(:authorization_event, :event_id))
        %i[snapshot_digest verification_digest].each do |field|
          key.failure("member #{index} #{field} must be a SHA-256 digest") unless Types::SHA256_DIGEST_PATTERN.match?(binding.fetch(field))
        end
        unless Types::SHA256_DIGEST_PATTERN.match?(member.fetch(:authorization_decision_digest))
          key.failure("member #{index} authorization_decision_digest must be a SHA-256 digest")
        end
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
