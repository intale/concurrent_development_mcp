# frozen_string_literal: true

module Coordinator::Write
  module ProcessSteps
    class FindOrPlanProcessStepV1 < Value
      attribute :command_id, Types::UuidV7
      attribute :event_id, Types::UuidV7
      attribute :process_step_id, Types::UuidV7
      attribute :process_name, Types::Identifier
      attribute :step_name, Types::Identifier
      attribute :source_event_id, Types::UuidV7
      attribute :subject_kind, Types::Identifier
      attribute :subject_id, Types::Identifier
      attribute :target_command_id, Types::UuidV7
      attribute :target_entity_id, Types::UuidV7.optional
      attribute :rule_version, Types::String.constrained(min_size: 1, max_size: 200)
    end
  end
end
