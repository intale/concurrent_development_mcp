# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class CompletionGuaranteeV1 < Value
      attribute :scope, Types::String.enum("command", "saga", "request")
      attribute :outcome, Types::String.enum("succeeded", "denied", "failed", "partial_failure", "cancelled")
      attribute :effects, Types::String.enum("committed", "unchanged", "none", "partial", "unknown")
      attribute :read_back_required, Types::Strict::Bool.constrained(eql: false)
      attribute :read_models, Types::String.enum("eventually_consistent")
    end
  end
end
