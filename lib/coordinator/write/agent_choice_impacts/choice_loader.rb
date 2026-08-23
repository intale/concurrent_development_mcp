# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class ChoiceLoader
      def initialize(
        event_store:,
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new,
        partition_selector: DecisionContexts::PartitionSelector.new,
        canonical_json: CanonicalJson.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
        @partition_selector = partition_selector
        @canonical_json = canonical_json
      end

      def call(choice_id:, accepted_choice:)
        events = @event_store.read(
          @stream_factory.agent_choice(choice_id),
          EventQueries::AGENT_CHOICE_FOR_IMPACT
        )
        payloads = events.map { load(_1) }
        validate_history!(choice_id, accepted_choice, events, payloads)

        ChoiceSnapshotV1.new(
          choice_id:,
          recorded: payloads.fetch(0),
          recorded_event: reference(events.fetch(0)),
          accepted: payloads.fetch(1),
          accepted_event: reference(events.fetch(1)),
          invalidation: payloads.fetch(2, nil),
          invalidation_event: events[2] && reference(events.fetch(2))
        )
      end

      private

      def validate_history!(choice_id, expected_accepted, events, payloads)
        expected_types = [ Events::AgentChoiceRecordedV1, Events::AgentChoiceAcceptedV1 ]
        expected_types << Events::AgentChoiceInvalidatedByDecisionV1 if payloads.length == 3
        unless payloads.length.between?(2, 3) && payloads.map(&:class) == expected_types
          invalid!("choice_lifecycle_invalid", choice_id:, event_types: events.map(&:type))
        end

        recorded = payloads.fetch(0)
        accepted = payloads.fetch(1)
        recorded_reference = reference(events.fetch(0))
        accepted_reference = reference(events.fetch(1))
        valid_identity = recorded.choice_id == choice_id &&
                         accepted.choice_id == choice_id &&
                         recorded_reference.stream_revision == 0 &&
                         accepted_reference.stream_revision == 1 &&
                         accepted.recorded_event == recorded_reference &&
                         accepted.context_digest == recorded.decision_context.digest &&
                         accepted_reference == expected_accepted
        unless valid_identity
          invalid!(
            "choice_identity_invalid",
            choice_id:,
            expected_accepted: expected_accepted.to_h,
            persisted_accepted: accepted_reference.to_h
          )
        end

        validate_context!(recorded)
        validate_invalidation!(choice_id, accepted_reference, events, payloads)
      end

      def validate_context!(recorded)
        context = recorded.decision_context
        document = context.document
        expected_partitions = @partition_selector.call(recorded.context)
        canonical_digest = @canonical_json.sha256(document.to_h)
        observations_valid = document.partitions.map(&:partition) == expected_partitions &&
                             document.partitions.all? { valid_observation?(_1) }
        unless document.query_context == recorded.context &&
               context.digest == canonical_digest &&
               observations_valid
          invalid!(
            "recorded_context_invalid",
            choice_id: recorded.choice_id,
            context_digest: context.digest
          )
        end
      end

      def valid_observation?(observation)
        if observation.partition_revision.nil?
          return observation.event.nil? && observation.active_decisions.empty?
        end

        event = observation.event
        heads = observation.active_decisions
        event &&
          event.type == "DecisionPartitionAdvanced" &&
          event.stream_context == "HumanGuidance" &&
          event.stream_name == "DecisionPartition" &&
          event.stream_id == observation.partition.partition_id &&
          event.stream_revision == observation.partition_revision &&
          heads.map(&:decision_id).uniq.length == heads.length &&
          heads == heads.sort_by { _1.decision_id.b } &&
          heads.all? { exact_decision_head?(_1) }
      end

      def exact_decision_head?(head)
        head.decision_revision == head.event.stream_revision &&
          head.event.stream_context == "HumanGuidance" &&
          head.event.stream_name == "Decision" &&
          head.event.stream_id == head.decision_id
      end

      def validate_invalidation!(choice_id, accepted_reference, events, payloads)
        invalidation = payloads.fetch(2, nil)
        return unless invalidation

        invalidation_reference = reference(events.fetch(2))
        assessment_event = read_reference(invalidation.assessment_event)
        assessment = assessment_event && load(assessment_event)
        valid = invalidation_reference.stream_revision == 2 &&
                invalidation.choice_id == choice_id &&
                invalidation.accepted_choice == accepted_reference &&
                invalidation.assessment_event.type == "AgentChoiceImpactAssessed" &&
                invalidation.assessment_event.stream_context == "AgentGovernance" &&
                invalidation.assessment_event.stream_name == "AgentChoiceImpact" &&
                assessment.is_a?(Events::AgentChoiceImpactAssessedV1) &&
                assessment.choice_id == choice_id &&
                assessment.accepted_choice == accepted_reference &&
                assessment.decision_change.source_event == invalidation.decision_change_event &&
                assessment.assessment.outcome == "invalidated" &&
                assessment.assessment.before_context_digest == invalidation.previous_context_digest &&
                assessment.assessment.after_context_digest == invalidation.resulting_context_digest &&
                assessment.assessment.reason == invalidation.reason
        invalid!("choice_invalidation_invalid", choice_id:) unless valid
      end

      def read_reference(reference)
        event = @event_store.read_at(
          StreamReference.new(
            context: reference.stream_context,
            stream_name: reference.stream_name,
            stream_id: reference.stream_id
          ),
          reference.stream_revision
        )
        event if event && self.reference(event) == reference
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def invalid!(reason, evidence)
        raise InvalidHistory.new(reason:, evidence:)
      end
    end
  end
end
