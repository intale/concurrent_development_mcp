# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class Decisions
      TOOLS = %w[decision_interpretation_propose decision_interpretation_adjudicate decision_activate decision_correct agent_choice_record].freeze

      def initialize(facts:)
        @facts = facts
      end

      def call(source)
        case source.tool_name
        when "decision_interpretation_propose"
          source.presentation("Atomic decision interpretation proposed without activating policy.",
            source.values(:interpretation_id, :source_message_id).merge(assessment: source.fact("DecisionInterpretationProposed").fetch(:assessment), proposed_at: source.completed_at),
            next_actions: [ source.action("decision_interpretation_list", message_id: source.input.fetch(:source_message_id)) ])
        when "decision_interpretation_adjudicate" then adjudication(source)
        when "decision_activate" then activation(source)
        when "decision_correct" then correction(source)
        when "agent_choice_record" then choice(source)
        end
      end

      private

      def adjudication(source)
        action = source.input.fetch(:action)
        source.presentation("Interpretation adjudication recorded without activating policy.",
          source.values(:interpretation_id, :source_message_id, :action).merge(
            outcome: { "accept" => "accepted_for_activation", "reject" => "rejected", "request_clarification" => "clarification_required" }.fetch(action),
            policy_status: "proposal_only", slot: action == "accept" ? source.fact("DecisionInterpretationAccepted").fetch(:slot) : nil,
            adjudicated_at: source.completed_at
          ), next_actions: [ source.action("decision_interpretation_list", message_id: source.input.fetch(:source_message_id)) ])
      end

      def activation(source)
        definition = source.fact("DecisionRecorded").fetch(:definition)
        opened = source.event("DecisionSlotOpened")
        source.presentation("Accepted interpretation activated as authoritative policy.", source.values(:decision_id, :interpretation_id).merge(
          outcome: "activated", policy_status: "active", definition_digest: digest(definition),
          slot: opened && slot(source.data(opened).fetch(:slot_id), source.data(opened).fetch(:slot)),
          partitions: partitions(source, [ definition ]), activated_at: source.completed_at
        ), next_actions: [ source.action("decision_get", **source.values(:decision_id)) ])
      end

      def correction(source)
        event = source.event("DecisionDefinitionCorrected")
        definition = source.data(event).fetch(:definition)
        previous = @facts.previous(:decision, source.input.fetch(:decision_id), %w[DecisionRecorded DecisionDefinitionCorrected], event.stream_revision - 1)
        before = source.data(previous).fetch(:definition)
        changed = source.events("DecisionSlotHeadChanged").reverse.find { _1.data["head"]&.fetch("decision_id") == source.input.fetch(:decision_id) }
        source.presentation("Active Decision definition corrected from accepted interpretation evidence.", source.values(:decision_id, :interpretation_id).merge(
          outcome: "corrected", policy_status: "active", previous_definition_digest: digest(before), definition_digest: digest(definition),
          correction_event: source.reference(event), slot: changed && slot(changed.data.fetch("slot_id"), slot_document(definition)),
          partitions: partitions(source, [ before, definition ]), corrected_at: source.completed_at
        ), next_actions: [ source.action("decision_get", **source.values(:decision_id)) ])
      end

      def choice(source)
        accepted = source.event("AgentChoiceAccepted")
        assessment = source.data(accepted).fetch(:assessment)
        source.presentation("Agent choice recorded and accepted against authoritative Decision context.", source.values(:choice_id, :choice_type).merge(
          outcome: "accepted", assessment_basis: assessment.fetch(:basis), context_digest: accepted.metadata.fetch("context_digest"),
          recorded_event: source.reference(source.event("AgentChoiceRecorded")), accepted_event: source.reference(accepted),
          based_on_decisions: assessment.fetch(:based_on_decisions), warnings: assessment.fetch(:warnings), accepted_at: source.completed_at
        ), next_actions: [ source.action("agent_choice_get", **source.values(:choice_id)) ])
      end

      def partitions(source, definitions)
        descriptors = definitions.flat_map { partition_descriptors(_1) }.to_h { [ _1.fetch(:partition_id), _1 ] }
        source.events("DecisionAddedToPartition", "DecisionRemovedFromPartition").map do |event|
          { partition: descriptors.fetch(event.data.fetch("partition_id")), partition_revision: event.stream_revision }
        end
      end

      def partition_descriptors(definition)
        scope, root = definition.fetch(:scope), definition.fetch(:topic).fetch(:topic_id).split(".", 2).first
        anchor = [ [ :candidate_id, "candidate" ], [ :attempt_id, "attempt" ], [ :work_item_id, "workitem" ], [ :change_set_id, "changeset" ] ]
          .find { |key, _| scope[key] }
        anchors = if anchor
                    [ [ anchor.last, scope.fetch(anchor.first) ] ]
        elsif scope.fetch(:repository_ids).any?
                    scope.fetch(:repository_ids).uniq.map { [ "repo", _1 ] }
        elsif scope[:workspace_id]
                    [ [ "workspace", scope.fetch(:workspace_id) ] ]
        else
                    []
        end
        anchors.map { |kind, id| { partition_id: "#{kind}:#{id}:#{root}", topic_root: root, anchor_kind: kind, anchor_id: id } }
      end

      def slot_document(definition)
        topic = definition.fetch(:topic)
        { schema: "decision-slot/v1", topic_id: topic.fetch(:topic_id), exact_scope: definition.fetch(:scope),
          exact_conditions: definition.fetch(:conditions), conflict_dimension: topic.fetch(:conflict_dimension), resolution_strategy: topic.fetch(:resolution_strategy) }
      end

      def slot(id, document)
        components = [ "topic:#{document.fetch(:topic_id)}", "conflict-dimension:#{document.fetch(:conflict_dimension)}",
          "resolution-strategy:#{document.fetch(:resolution_strategy)}" ]
        builder = Coordinator::Shared::CanonicalMarkerComponentBuilder.new
        components += builder.call(dimension: "scope", value: document.fetch(:exact_scope))
        components += builder.call(dimension: "conditions", value: document.fetch(:exact_conditions))
        marker = Coordinator::Shared::Markers::CodecV2.encode(purpose: "decision-slot",
          components: components.uniq.map { |component| dimension, _, value = component.partition(":"); { dimension:, value: } })
        { slot_id: id, document:, compound_marker: { purpose: "decision-slot", components: components.uniq.sort_by(&:b),
          digest: digest(schema: "coordinator-compound-marker/v1", purpose: "decision-slot", components: components.uniq.sort_by(&:b)), marker: } }
      end

      def digest(document)
        Coordinator::Shared::CanonicalJson.new.sha256(document)
      end
    end
  end
end
