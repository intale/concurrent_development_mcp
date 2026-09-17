# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    module PostRemodelEvents
      class CandidateHeadRegisteredV2 < Events::CandidateHeadRegisteredV2
        contract type: "CandidateHeadRegistered", version: 2

        attribute? :candidate_event, EventReference.optional
        attribute? :registered_at, Types::Timestamp.optional
      end

      class CoordinationTaskSubmittedV3 < Events::Base
        contract type: "CoordinationTaskSubmitted", version: 3

        attribute :task_id, Types::TaskId
        attribute :command_id, Types::CommandId
        attribute :tool_name, Types::CoordinationToolName
        attribute :command_input, PostRemodelCommandInputDocuments::Type
        attribute :poll_interval_ms, Types::Integer.constrained(eql: 500)
        attribute :ttl_ms, Types::Nil
      end
    end
  end
end
