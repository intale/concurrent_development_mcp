# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class CandidateSourceEvent < Dry::Validation::Contract
      SCHEMA_VERSION_BY_EVENT_TYPE = {
        "CandidateCreated" => 1,
        "CandidateAssignedToAttempt" => 1,
        "CandidateAssignedToRepository" => 1,
        "CandidateTargetBranchSelected" => 1,
        "CandidateCommitRangeDeclared" => 1,
        "CandidateCheckpointKindSelected" => 1,
        "CandidateWorkIntentionSetAssigned" => 1,
        "CandidateChangeManifestCaptured" => 2,
        "CandidateBuildContextCaptured" => 2,
        "CandidateSubmitted" => 3,
        "CandidateImpactSurfaceAssigned" => 1
      }.freeze
      EVENT_TYPES = SCHEMA_VERSION_BY_EVENT_TYPE.keys.freeze

      config.validate_keys = true

      params do
        required(:event_type).filled(:string, included_in?: EVENT_TYPES)
        required(:schema_version).filled(:integer, included_in?: [ 1, 2, 3 ])
        required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
        required(:stream_name).filled(:string, eql?: "Candidate")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:global_position).filled(:integer, gteq?: 0)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string, eql?: "agent")
        required(:actor_id).filled(:string)
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).maybe(:string)
      end

      rule(:event_type, :schema_version) do
        expected = SCHEMA_VERSION_BY_EVENT_TYPE.fetch(values[:event_type])
        key(:schema_version).failure("must match the projected event schema") unless values[:schema_version] == expected
      end

      rule(:event_type, :policy_version) do
        expected = case values[:event_type]
                   when "CandidateWorkIntentionSetAssigned"
                     Coordinator::Write::LeaseResourceV2::POLICY_VERSION
                   when "CandidateChangeManifestCaptured"
                     Coordinator::Write::Candidates::ChangeManifestDocumentV1::SCHEMA
                   when "CandidateBuildContextCaptured"
                     Coordinator::Write::Candidates::BuildContextDocumentV1::SCHEMA
                   end
        unless values[:policy_version] == expected
          key(:policy_version).failure("must match the projected event policy")
        end
      end

      rule(:stream_id, :command_id, :actor_id) do
        values.values_at(:stream_id, :command_id, :actor_id).each do |identifier|
          next if Types::IDENTIFIER_PATTERN.match?(identifier)

          key.failure("stream, command, and actor IDs must be valid identifiers")
          break
        end
      end
    end
  end
end
