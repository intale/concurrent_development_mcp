# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class CandidateSourceEvent < Dry::Validation::Contract
      REVISION_BY_EVENT_TYPE = {
        "CandidateSubmitted" => 0,
        "CandidateChangeManifestCaptured" => 1,
        "CandidateBuildContextCaptured" => 2
      }.freeze
      EVENT_TYPES = REVISION_BY_EVENT_TYPE.keys.freeze

      config.validate_keys = true

      params do
        required(:event_type).filled(:string, included_in?: EVENT_TYPES)
        required(:schema_version).filled(:integer, eql?: 1)
        required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
        required(:stream_name).filled(:string, eql?: "Candidate")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:global_position).filled(:integer, gteq?: 0)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string, eql?: "agent")
        required(:actor_id).filled(:string)
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).filled(
          :string,
          eql?: Coordinator::Write::ResourceKeyDocumentV1::POLICY_VERSION
        )
      end

      rule(:event_type, :stream_revision) do
        next if values[:stream_revision] == REVISION_BY_EVENT_TYPE.fetch(values[:event_type])

        key(:stream_revision).failure("must match the Candidate evidence chronology")
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
