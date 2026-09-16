# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DecisionPartitionIdentityMapper
      include Dry::Monads[:result]

      ANCHOR_TARGETS = {
        "repo" => [ "DevelopmentPlanning", "Repository", "repository" ],
        "changeset" => [ "DevelopmentPlanning", "ChangeSet", "change-set" ],
        "workitem" => [ "DevelopmentExecution", "WorkItem", "work-item" ],
        "attempt" => [ "DevelopmentExecution", "Attempt", "attempt" ],
        "candidate" => [ "DevelopmentIntegration", "Candidate", "candidate" ]
      }.freeze

      def initialize(entity_reference_resolver:)
        @entity_reference_resolver = entity_reference_resolver
      end

      def call(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        partition:
      )
        target = ANCHOR_TARGETS[partition.anchor_kind]
        return Success(rebuild(partition, anchor_id: partition.anchor_id)) unless target

        allocation = @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: target.fetch(0),
            stream_name: target.fetch(1),
            stream_id: partition.anchor_id
          ),
          target_stream_context: target.fetch(0),
          target_stream_name: target.fetch(1),
          identity_role: target.fetch(2)
        )
        return allocation if allocation.failure?

        Success(rebuild(partition, anchor_id: allocation.value!.target_stream.stream_id))
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def rebuild(partition, anchor_id:)
        Decisions::DecisionPartitionV1.new(
          partition_id: "#{partition.anchor_kind}:#{anchor_id}:#{partition.topic_root}",
          topic_root: partition.topic_root,
          anchor_kind: partition.anchor_kind,
          anchor_id:
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Decision partition identity is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
