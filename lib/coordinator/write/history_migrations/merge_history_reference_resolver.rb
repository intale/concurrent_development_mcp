# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MergeHistoryReferenceResolver
      include Dry::Monads[:result]

      TARGETS = {
        "CandidateSubmitted" =>
          [ "DevelopmentIntegration", "Candidate", "candidate", "CandidateSubmitted", "submit-candidate" ],
        "CandidateChangeManifestCaptured" => [
          "DevelopmentIntegration", "Candidate", "candidate",
          "CandidateChangeManifestCaptured", "capture-candidate-change-manifest"
        ],
        "CandidateImpactSurfaceDerived" => [
          "DevelopmentIntegration", "CandidateImpactSurface", "candidate-impact-surface",
          "CandidateImpactSurfaceDerived", "derive-candidate-impact-surface"
        ],
        "WorkItemCandidateSelected" => [
          "DevelopmentExecution", "WorkItem", "work-item",
          "WorkItemCandidateSelected", "select-work-item-candidate"
        ],
        "WorkItemCompleted" =>
          [ "DevelopmentExecution", "WorkItem", "work-item", "WorkItemCompleted", "complete-work-item" ],
        "WorkItemDependencySatisfied" => [
          "DevelopmentExecution", "WorkItem", "work-item",
          "WorkItemDependencySatisfied", "satisfy-work-item-dependency"
        ],
        "VerificationObligationCreated" => [
          "DevelopmentIntegration", "VerificationObligation", "verification-obligation",
          "VerificationObligationCreated", "create-verification-obligation"
        ],
        "VerificationObligationSatisfied" => [
          "DevelopmentIntegration", "VerificationObligation", "verification-obligation",
          "VerificationObligationSatisfied", "satisfy-verification-obligation"
        ],
        "VerificationObligationFailed" => [
          "DevelopmentIntegration", "VerificationObligation", "verification-obligation",
          "VerificationObligationFailed", "fail-verification-obligation"
        ],
        "VerificationObligationWaived" => [
          "DevelopmentIntegration", "VerificationObligation", "verification-obligation",
          "VerificationObligationWaived", "waive-verification-obligation"
        ],
        "VerificationObligationInvalidated" => [
          "DevelopmentIntegration", "VerificationObligation", "verification-obligation",
          "VerificationObligationInvalidated", "invalidate-verification-obligation"
        ],
        "DecisionActivated" =>
          [ "HumanGuidance", "Decision", "decision", "DecisionActivated", "activate-decision" ],
        "DecisionDefinitionCorrected" => [
          "HumanGuidance", "Decision", "decision",
          "DecisionDefinitionCorrected", "correct-decision-definition"
        ],
        "MergeSnapshotRegistered" => [
          "DevelopmentIntegration", "MergeSnapshot", "merge-snapshot",
          "MergeSnapshotRegistered", "register-merge-snapshot"
        ],
        "MergeSnapshotVerificationSubmitted" => [
          "DevelopmentIntegration", "MergeVerification", "merge-verification",
          "MergeSnapshotVerificationSubmitted", "submit-merge-snapshot-verification"
        ],
        "MergeSnapshotVerificationSelected" => [
          "DevelopmentIntegration", "MergeSnapshot", "merge-snapshot",
          "MergeSnapshotVerificationSelected", "select-merge-snapshot-verification"
        ],
        "MergeSnapshotVerified" => [
          "DevelopmentIntegration", "MergeSnapshot", "merge-snapshot",
          "MergeSnapshotVerified", "verify-merge-snapshot"
        ],
        "MergeAuthorizationGranted" => [
          "DevelopmentIntegration", "MergeAuthorization", "merge-authorization",
          "MergeAuthorizationGranted", "grant-merge-authorization"
        ],
        "MergeAuthorizationDenied" => [
          "DevelopmentIntegration", "MergeAuthorization", "merge-authorization",
          "MergeAuthorizationDenied", "deny-merge-authorization"
        ]
      }.freeze

      def initialize(
        event_store:,
        entity_reference_resolver:,
        target_event_reference_resolver:,
        partition_identity_mapper:,
        partition_delta_resolver:,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @entity_reference_resolver = entity_reference_resolver
        @target_event_reference_resolver = target_event_reference_resolver
        @partition_identity_mapper = partition_identity_mapper
        @partition_delta_resolver = partition_delta_resolver
        @schema_registry = schema_registry
      end

      def call(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_reference:
      )
        case source_reference.type
        when "CandidateImpactSurfaceRegistered"
          loaded = load_reference(source_event:, source_upper_position:, source_reference:)
          return loaded if loaded.failure?

          resolve_candidate_impact_assignment(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_reference:,
            payload: loaded.value!.last
          )
        when "WorkItemDependencyDeclared"
          loaded = load_reference(source_event:, source_upper_position:, source_reference:)
          return loaded if loaded.failure?

          resolve_dependency_declaration(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_reference:,
            payload: loaded.value!.last
          )
        when "DecisionPartitionAdvanced"
          loaded = load_reference(source_event:, source_upper_position:, source_reference:)
          return loaded if loaded.failure?

          resolve_partition_event(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_reference:,
            referenced_event: loaded.value!.first,
            payload: loaded.value!.last
          )
        else
          resolve_regular(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_reference:
          )
        end
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def load_reference(source_event:, source_upper_position:, source_reference:)
        event = @event_store.read_at(stream_for(source_reference), source_reference.stream_revision)
        unless event && event.id == source_reference.event_id && event.type == source_reference.type &&
            event.global_position <= source_upper_position
          return Failure(inconsistent(source_event, "referenced event is absent from the frozen source range"))
        end

        Success([ event, load(event) ])
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def resolve_regular(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_reference:
      )
        target = TARGETS[source_reference.type]
        return Failure(inconsistent(source_event, "unsupported reference type #{source_reference.type}")) unless target

        @target_event_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference:,
          target_stream_context: target.fetch(0),
          target_stream_name: target.fetch(1),
          identity_role: target.fetch(2),
          target_event_type: target.fetch(3),
          target_step_name: target.fetch(4)
        )
      end

      def resolve_candidate_impact_assignment(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_reference:,
        payload:
      )
        unless payload.is_a?(Events::CandidateImpactSurfaceRegisteredV1)
          return Failure(inconsistent(source_event, "Candidate impact assignment contract is invalid"))
        end

        candidate = resolve_regular(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: payload.candidate_event
        )
        return candidate if candidate.failure?

        target_candidate = candidate.value!
        @target_event_reference_resolver.call_in_stream(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference:,
          target_stream: StreamReference.new(
            context: target_candidate.stream_context,
            stream_name: target_candidate.stream_name,
            stream_id: target_candidate.stream_id
          ),
          target_event_type: "CandidateImpactSurfaceAssigned",
          target_step_name: "assign-candidate-impact-surface"
        )
      end

      def resolve_dependency_declaration(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_reference:,
        payload:
      )
        unless payload.is_a?(Events::WorkItemDependencyDeclaredV1)
          return Failure(inconsistent(source_event, "WorkItem dependency declaration contract is invalid"))
        end

        consumer = @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: "DevelopmentExecution",
            stream_name: "WorkItem",
            stream_id: payload.consumer_work_item_id
          ),
          target_stream_context: "DevelopmentExecution",
          target_stream_name: "WorkItem",
          identity_role: "work-item"
        )
        return consumer if consumer.failure?

        @target_event_reference_resolver.call_in_stream(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference:,
          target_stream: consumer.value!.target_stream,
          target_event_type: "WorkItemDependencyDeclared",
          target_step_name: "declare-work-item-dependency"
        )
      end

      def resolve_partition_event(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_reference:,
        referenced_event:,
        payload:
      )
        unless payload.is_a?(Events::DecisionPartitionAdvancedV1)
          return Failure(inconsistent(source_event, "Decision partition contract is invalid"))
        end

        partition = @partition_identity_mapper.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          partition: payload.partition
        )
        return partition if partition.failure?

        delta = @partition_delta_resolver.call(
          source_event: referenced_event,
          source_upper_position:
        )
        return delta if delta.failure?

        step_name, event_type = if delta.value!.add
          [ "add-decision-to-partition", "DecisionAddedToPartition" ]
        else
          [ "remove-decision-from-partition", "DecisionRemovedFromPartition" ]
        end
        @target_event_reference_resolver.call_in_stream(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference:,
          target_stream: StreamReference.new(
            context: "HumanGuidance",
            stream_name: "DecisionPartition",
            stream_id: partition.value!.partition_id
          ),
          target_event_type: event_type,
          target_step_name: step_name
        )
      end

      def stream_for(reference)
        StreamReference.new(
          context: reference.stream_context,
          stream_name: reference.stream_name,
          stream_id: reference.stream_id
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Merge history reference is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
