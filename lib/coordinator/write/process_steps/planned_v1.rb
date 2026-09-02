# frozen_string_literal: true

module Coordinator::Write::ProcessSteps
  class PlannedV1 < Coordinator::Write::Value
    attribute :process_step_id, Coordinator::Write::Types::UuidV7
    attribute :target_command_id, Coordinator::Write::Types::UuidV7
    attribute :target_entity_id, Coordinator::Write::Types::UuidV7.optional
    attribute :event, Coordinator::Write::Types.Instance(PgEventstore::Event)
    attribute :reference, Coordinator::Write::EventReference
    attribute :outcome, Coordinator::Write::Types::String.enum("created", "existing")

    def target_entity_id!
      target_entity_id || raise(InvalidProcessStepPlan, "Process step did not allocate a target entity")
    end
  end
end
