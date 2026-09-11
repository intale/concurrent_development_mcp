# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class VerificationObligationSourceEvent < Dry::Validation::Contract
      EVENT_TYPES = [
        "VerificationObligationCreated",
        "VerificationObligationAddedToChangeSet",
        "VerificationObligationSourceCandidateAssigned",
        "VerificationObligationTargetCandidateAssigned",
        "VerificationObligationClaimed",
        "VerificationEvidenceSubmitted",
        "VerificationObligationEvidenceSelected",
        "VerificationObligationSatisfied",
        "VerificationObligationFailed",
        "VerificationObligationWaived",
        "VerificationObligationInvalidated"
      ].freeze

      SCHEMA_VERSIONS = {
        "VerificationObligationCreated" => [ 1, 2 ],
        "VerificationObligationAddedToChangeSet" => [ 1 ],
        "VerificationObligationSourceCandidateAssigned" => [ 1 ],
        "VerificationObligationTargetCandidateAssigned" => [ 1 ],
        "VerificationObligationClaimed" => [ 1, 2 ],
        "VerificationEvidenceSubmitted" => [ 1, 2 ],
        "VerificationObligationEvidenceSelected" => [ 1 ],
        "VerificationObligationSatisfied" => [ 1, 2 ],
        "VerificationObligationFailed" => [ 1, 2 ],
        "VerificationObligationWaived" => [ 1, 2 ],
        "VerificationObligationInvalidated" => [ 1, 2 ]
      }.freeze

      config.validate_keys = true

      params do
        required(:event_type).filled(:string, included_in?: EVENT_TYPES)
        required(:schema_version).filled(:integer)
        required(:stream_context).filled(:string, eql?: "DevelopmentIntegration")
        required(:stream_name).filled(:string, eql?: "VerificationObligation")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:global_position).filled(:integer, gteq?: 0)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string, included_in?: %w[agent system user])
        required(:actor_id).filled(:string)
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).filled(:string)
      end

      rule(:stream_id, :command_id) do
        identifiers = values.values_at(:stream_id, :command_id)
        next if identifiers.all? { Types::IDENTIFIER_PATTERN.match?(_1) }

        key.failure("stream and command IDs must be valid identifiers")
      end

      rule(:event_type, :schema_version, :stream_id, :stream_revision, :command_id, :actor_kind, :actor_id, :policy_version) do
        version = values[:schema_version]
        unless SCHEMA_VERSIONS.fetch(values[:event_type]).include?(version)
          key(:schema_version).failure("is not supported for this verification-obligation fact")
          next
        end

        valid = case values[:event_type]
        when "VerificationObligationCreated"
          values[:stream_revision].zero? &&
            Types::UUID_V7_PATTERN.match?(values[:stream_id]) &&
            Types::UUID_V7_PATTERN.match?(values[:command_id]) &&
            values[:stream_id] != values[:command_id] &&
            values[:actor_kind] == "system" &&
            values[:actor_id] == "candidate-impact-obligation-policy" &&
            values[:policy_version] == "candidate-compatibility-obligation/v1"
        when "VerificationObligationAddedToChangeSet"
          values[:stream_revision] == 1 && definition_fact?(values)
        when "VerificationObligationSourceCandidateAssigned"
          values[:stream_revision] == 2 && definition_fact?(values)
        when "VerificationObligationTargetCandidateAssigned"
          values[:stream_revision] == 3 && definition_fact?(values)
        when "VerificationObligationClaimed"
          values[:stream_revision].positive? &&
            values[:actor_kind] == "agent" &&
            values[:policy_version] == "verification-obligation-claim/v1"
        when "VerificationEvidenceSubmitted"
          values[:stream_revision] >= 2 &&
            values[:actor_kind] == "agent" &&
            values[:policy_version] == "compatibility-assessment/v#{version}"
        when "VerificationObligationEvidenceSelected"
          values[:stream_revision].positive? &&
            values[:actor_kind] == "system" &&
            values[:actor_id] == "verification-evidence-outcome" &&
            values[:policy_version] == "verification-obligation-outcome/v2"
        when "VerificationObligationSatisfied", "VerificationObligationFailed"
          values[:stream_revision] >= 3 &&
            outcome_source?(values, version)
        when "VerificationObligationWaived"
          values[:stream_revision].positive? &&
            values[:actor_kind] == "user" &&
            values[:policy_version] == "verification-obligation-waiver/v#{version}"
        when "VerificationObligationInvalidated"
          values[:stream_revision].positive? &&
            values[:actor_kind] == "system" &&
            values[:actor_id] == "verification-obligation-validity-policy" &&
            values[:policy_version] == "verification-obligation-validity/v1"
        else
          false
        end
        key(:event_type).failure("must use the exact event-specific source contract") unless valid
      end

      private

      def definition_fact?(values)
        values[:actor_kind] == "system" &&
          values[:actor_id] == "candidate-impact-obligation-policy" &&
          values[:policy_version] == "candidate-compatibility-obligation/v1"
      end

      def outcome_source?(values, version)
        if version == 1
          values[:actor_kind] == "agent" &&
            values[:policy_version] == "compatibility-assessment/v1"
        else
          values[:actor_kind] == "system" &&
            values[:actor_id] == "verification-evidence-outcome" &&
            values[:policy_version] == "verification-obligation-outcome/v2"
        end
      end
    end
  end
end
