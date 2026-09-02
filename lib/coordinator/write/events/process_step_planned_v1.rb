# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ProcessStepPlannedV1 < Base
      contract type: "ProcessStepPlanned", version: 1

      attribute :process_step_id, Types::UuidV7
      attribute :process_name, Types::Identifier
      attribute :step_name, Types::Identifier
      attribute :source_event_id, Types::UuidV7
      attribute :subject_kind, Types::Identifier
      attribute :subject_id, Types::Identifier
      attribute :target_command_id, Types::UuidV7
      attribute :target_entity_id, Types::UuidV7.optional
    end
  end
end
