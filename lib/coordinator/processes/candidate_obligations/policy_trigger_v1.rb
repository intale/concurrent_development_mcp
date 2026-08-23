# frozen_string_literal: true

module Coordinator::Processes
  module CandidateObligations
    class PolicyTriggerV1 < Value
      attribute :change_set_id, Types::Identifier
      attribute :partition_event, Coordinator::Write::EventReference
      attribute :head, Coordinator::Write::Decisions::DecisionHeadV1
    end
  end
end
