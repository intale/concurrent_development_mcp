# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class AgentChoiceImpactSourceEvent < Dry::Validation::Contract
      EVENT_DEFINITION_BY_TYPE = {
        "AgentChoiceImpactAssessmentRecorded" => [ 1, "AgentChoiceImpact", 0..0 ],
        "AgentChoiceImpactSourceLinked" => [ 1, "AgentChoiceImpact", 1..2 ],
        "AgentChoiceInvalidatedByDecision" => [ 2, "AgentChoice", 2..2 ]
      }.freeze
      EVENT_TYPES = EVENT_DEFINITION_BY_TYPE.keys.freeze

      config.validate_keys = true

      params do
        required(:event_type).filled(:string, included_in?: EVENT_TYPES)
        required(:schema_version).filled(:integer, included_in?: [ 1, 2 ])
        required(:stream_context).filled(:string, eql?: "AgentGovernance")
        required(:stream_name).filled(:string)
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:global_position).filled(:integer, gteq?: 0)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string, eql?: "system")
        required(:actor_id).filled(:string, eql?: "agent-choice-decision-impact")
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).filled(:string, eql?: "agent-choice-decision-impact/v1")
        optional(:before_context_digest).maybe(:string)
        optional(:after_context_digest).maybe(:string)
        optional(:previous_context_digest).maybe(:string)
        optional(:resulting_context_digest).maybe(:string)
      end

      rule(:event_type, :schema_version, :stream_name, :stream_revision) do
        expected_version, expected_name, expected_revisions = EVENT_DEFINITION_BY_TYPE.fetch(values[:event_type])
        unless values[:schema_version] == expected_version &&
               values[:stream_name] == expected_name &&
               expected_revisions.cover?(values[:stream_revision])
          key(:stream_name).failure("must match the AgentChoice impact lifecycle position")
        end
      end

      rule(:stream_id, :command_id) do
        unless Types::IDENTIFIER_PATTERN.match?(values[:stream_id]) &&
               Types::IDENTIFIER_PATTERN.match?(values[:command_id])
          key(:stream_id).failure("stream and command IDs must be valid identifiers")
        end
      end

      rule(
        :event_type,
        :before_context_digest,
        :after_context_digest,
        :previous_context_digest,
        :resulting_context_digest
      ) do
        before_digest = values[:before_context_digest]
        after_digest = values[:after_context_digest]
        previous_digest = values[:previous_context_digest]
        resulting_digest = values[:resulting_context_digest]
        case values[:event_type]
        when "AgentChoiceImpactAssessmentRecorded"
          valid = Types::SHA256_DIGEST_PATTERN.match?(before_digest.to_s) &&
                  Types::SHA256_DIGEST_PATTERN.match?(after_digest.to_s) &&
                  before_digest != after_digest &&
                  previous_digest.nil? && resulting_digest.nil?
          key(:before_context_digest).failure("must describe the exact context transition") unless valid
        when "AgentChoiceImpactSourceLinked"
          unless [ before_digest, after_digest, previous_digest, resulting_digest ].all?(&:nil?)
            key(:before_context_digest).failure("source links must not duplicate context evidence")
          end
        when "AgentChoiceInvalidatedByDecision"
          valid = Types::SHA256_DIGEST_PATTERN.match?(previous_digest.to_s) &&
                  Types::SHA256_DIGEST_PATTERN.match?(resulting_digest.to_s) &&
                  previous_digest != resulting_digest &&
                  before_digest.nil? && after_digest.nil?
          key(:previous_context_digest).failure("must describe the invalidating context transition") unless valid
        end
      end
    end
  end
end
