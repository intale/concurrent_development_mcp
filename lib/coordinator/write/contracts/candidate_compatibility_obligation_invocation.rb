# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateCompatibilityObligationInvocation < Dry::Validation::Contract
      params do
        required(:invocation).value(Types.Instance(Coordinator::Write::CandidateCompatibilityObligationInvocation))
      end

      rule(:invocation) do
        invocation = value
        parent = invocation.caused_by
        reference = invocation.caused_by_reference
        persisted = parent.stream && !parent.stream_revision.nil? && !parent.global_position.nil?
        exact = reference.event_id == parent.id &&
                reference.type == parent.type &&
                reference.stream_context == parent.stream&.context &&
                reference.stream_name == parent.stream&.stream_name &&
                reference.stream_id == parent.stream&.stream_id &&
                reference.stream_revision == parent.stream_revision

        key.failure("causal parent must be a persisted event") unless persisted
        key.failure("causal parent must match its exact reference") unless exact
      end
    end
  end
end
