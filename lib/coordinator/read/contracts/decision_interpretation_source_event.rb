# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class DecisionInterpretationSourceEvent < Dry::Validation::Contract
      EVENT_TYPES = %w[
        DecisionInterpretationProposed
        DecisionClarificationRequired
      ].freeze

      params do
        required(:event_type).filled(:string, included_in?: EVENT_TYPES)
        required(:schema_version).filled(:integer, eql?: 1)
        required(:stream_context).filled(:string, eql?: "HumanGuidance")
        required(:stream_name).filled(:string, eql?: "Interpretation")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:actor_kind).filled(:string, included_in?: Types::ACTOR_KINDS)
        required(:actor_id).filled(:string)
      end

      rule(:stream_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end
    end
  end
end
