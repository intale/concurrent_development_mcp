# frozen_string_literal: true

module Coordinator::Read
  module AgentChoiceImpacts
    class DecisionChangeLoader
      def initialize(event_store:, partition_builder: Projections::DecisionPartitions.new, canonical_json: Coordinator::Shared::CanonicalJson.new)
        @event_store = event_store
        @partition_builder = partition_builder
        @canonical_json = canonical_json
      end

      def call(reference)
        event = @event_store.read_at(
          Coordinator::Write::StreamReference.new(
            context: reference.fetch(:stream_context),
            stream_name: reference.fetch(:stream_name),
            stream_id: reference.fetch(:stream_id)
          ),
          reference.fetch(:stream_revision)
        )
        payload = CommandResults::Source.document(event.data)
        definition = event.type == "DecisionActivated" ? definition_before(event) : payload.fetch(:definition)
        definitions = event.type == "DecisionActivated" ? [ definition ] : [ definition_before(event), definition ]
        evidence = {
          source_event: reference,
          source_global_position: event.global_position,
          source_command_id: event.metadata.fetch("command_id"),
          source_actor: {
            kind: event.metadata.fetch("actor_kind"),
            id: event.metadata.fetch("actor_id")
          },
          decision_id: payload.fetch(:decision_id),
          change_kind: event.type == "DecisionActivated" ? "activated" : "corrected",
          definition_digest: @canonical_json.sha256(definition),
          retroactivity: definition.fetch(:enforcement).fetch(:retroactivity),
          affected_partitions: definitions.flat_map { @partition_builder.call(_1) }.uniq { _1.fetch(:partition_id) }
            .sort_by { _1.fetch(:partition_id).b }
        }
        { evidence:, changed_at: event.created_at.utc.iso8601(6) }
      end

      private

      def definition_before(event)
        stream = Coordinator::Write::StreamReference.new(
          context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id
        )
        physical = @event_store.read_latest(
          stream,
          Coordinator::Write::LatestEventReadCriteria.new(
            event_types: %w[DecisionRecorded DecisionDefinitionCorrected],
            from_revision: event.stream_revision - 1
          )
        )
        CommandResults::Source.document(physical.data.fetch("definition"))
      end
    end
  end
end
