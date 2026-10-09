# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class DevelopmentArtifactSourceEvent < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:event_type).filled(
          :string,
          included_in?: %w[
            DevelopmentArtifactCreated
            DevelopmentArtifactScopeChanged
            DevelopmentArtifactTitleChanged
            DevelopmentArtifactKindChanged
            DevelopmentArtifactLabelAdded
            DevelopmentArtifactLabelRemoved
            DevelopmentArtifactSourceChanged
            DevelopmentArtifactContentChanged
            DevelopmentArtifactObservationRecorded
            DevelopmentArtifactObservationFactLinked
            DevelopmentArtifactClassificationCorrectionRecorded
            DevelopmentArtifactRelationDeclared
            DevelopmentArtifactRelationSuperseded
          ]
        )
        required(:schema_version).filled(:integer, included_in?: [ 1, 2 ])
        required(:stream_context).filled(:string, eql?: "DevelopmentMemory")
        required(:stream_name).filled(
          :string,
          included_in?: %w[
            DevelopmentArtifact
            DevelopmentArtifactObservation
            DevelopmentArtifactRelation
          ]
        )
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:global_position).filled(:integer, gteq?: 0)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string, included_in?: %w[agent user])
        required(:actor_id).filled(:string)
        required(:recorded_by).filled(:string, eql?: "coordinator")
          required(:policy_version).filled(
            :string,
            included_in?: %w[development-artifact-repository/v1 development-artifact-repository/v2]
          )
      end

      rule(:stream_id) do
        pattern =
          if values[:stream_name] == "DevelopmentArtifactObservation"
            Types::DEVELOPMENT_ARTIFACT_OBSERVATION_ID_PATTERN
          elsif values[:stream_name] == "DevelopmentArtifactRelation"
            Types::DEVELOPMENT_ARTIFACT_RELATION_ID_PATTERN
          else
            Types::DEVELOPMENT_ARTIFACT_ID_PATTERN
          end
        key.failure("must match the selected Artifact stream identity") unless pattern.match?(value)
      end

      rule(:event_type, :stream_name) do
        observation_event = %w[
          DevelopmentArtifactObservationRecorded
          DevelopmentArtifactObservationFactLinked
          DevelopmentArtifactClassificationCorrectionRecorded
        ].include?(values[:event_type])
        relation_event = %w[DevelopmentArtifactRelationDeclared DevelopmentArtifactRelationSuperseded].include?(values[:event_type])
        expected_stream = if observation_event
          "DevelopmentArtifactObservation"
        elsif relation_event
          "DevelopmentArtifactRelation"
        else
          "DevelopmentArtifact"
        end
        key(:stream_name).failure("does not carry this Artifact event type") unless values[:stream_name] == expected_stream
      end

      rule(:event_type, :schema_version) do
        expected_version = %w[DevelopmentArtifactRelationDeclared DevelopmentArtifactRelationSuperseded].include?(values[:event_type]) ? 2 : 1
        next if values[:schema_version] == expected_version

        key(:schema_version).failure("must be #{expected_version} for this Artifact event type")
      end

      rule(:command_id, :actor_id) do
        next if values.values_at(:command_id, :actor_id).all? { Types::IDENTIFIER_PATTERN.match?(_1) }

        key.failure("command and actor IDs must be valid identifiers")
      end
    end
  end
end
