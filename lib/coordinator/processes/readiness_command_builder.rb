# frozen_string_literal: true

module Coordinator::Processes
  class ReadinessCommandBuilder
    def initialize(compound_marker_builder: CompoundMarkerBuilder.new)
      @compound_marker_builder = compound_marker_builder
    end

    def call(source:, work_item_id:)
      document = Coordinator::Write::ProcessDecisions::ReadinessV1.new(
        schema: "process-decision/readiness/v1",
        process_manager: "change-set-readiness",
        policy_version: "change-set-readiness/v1",
        source_event: source.reference,
        target_work_item_id: work_item_id,
        process_step: "evaluate-work-item-readiness"
      )
      compound_marker = @compound_marker_builder.call(
        CompoundMarkerDefinitionV1.new(
          purpose: "process-decision",
          components: document.component_markers
        )
      )
      command_id = InternalCommandIdBuilder.call(
        "readiness-v1:#{compound_marker.digest.delete_prefix("sha256:")}"
      )
      identity = Coordinator::Write::ReadinessDecisionIdentity.new(document:, compound_marker:, command_id:)

      Coordinator::Write::Commands::EvaluateWorkItemReadiness.new(
        command_id:,
        actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "change-set-readiness"),
        change_set_id: source.payload.change_set_id,
        work_item_id:,
        source_activation_event_id: source.reference.event_id,
        source_activation_revision: source.reference.stream_revision,
        policy_version: document.policy_version,
        decision_identity: identity
      )
    end
  end
end
