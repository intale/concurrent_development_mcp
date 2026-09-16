# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CandidateImpactScanContextResolver
      include Dry::Monads[:result]

      PAIR_SOURCE_TYPES = [
        Events::CandidateImpactPairScanStartedV1,
        Events::CandidateImpactPairScanProgressedV1,
        Events::CandidateImpactPairScanSkippedV1,
        Events::CandidateImpactPairScanCompletedV1
      ].freeze
      REGISTRY_SOURCE_TYPES = [
        Events::CandidateImpactRegistrySweepStartedV1,
        Events::CandidateImpactRegistrySweepProgressedV1,
        Events::CandidateImpactRegistrySweepSkippedV1,
        Events::CandidateImpactRegistrySweepCompletedV1
      ].freeze

      def initialize(
        event_store:,
        stream_identity_allocator:,
        entity_reference_resolver:,
        target_event_reference_resolver:,
        candidate_context_resolver:,
        decision_partition_identity_mapper:,
        decision_partition_delta_resolver:,
        index_marker_builder:,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @entity_reference_resolver = entity_reference_resolver
        @target_event_reference_resolver = target_event_reference_resolver
        @candidate_context_resolver = candidate_context_resolver
        @decision_partition_identity_mapper = decision_partition_identity_mapper
        @decision_partition_delta_resolver = decision_partition_delta_resolver
        @index_marker_builder = index_marker_builder
        @schema_registry = schema_registry
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        family = family_for(source_event, source_payload)
        return family if family.failure?

        target_name, identity_role = family.value!
        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "DevelopmentIntegration",
          target_stream_name: target_name,
          identity_role:
        )
        return allocation if allocation.failure?

        change_set = resolve_change_set(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_id: source_payload.change_set_id
        )
        return change_set if change_set.failure?

        policy_head = resolve_policy_head(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_head: source_payload.policy_head
        )
        return policy_head if policy_head.failure?

        policy_partition = resolve_policy_partition(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source_payload.policy_partition_event,
          source_head: source_payload.policy_head
        )
        return policy_partition if policy_partition.failure?

        registration = resolve_registration(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_payload:
        )
        return registration if registration.failure?

        source_registration, routing_markers = registration.value!
        target_stream = allocation.value!.target_stream
        Success(
          CandidateImpactScanContextV1.new(
            target_stream:,
            scan_id: target_stream.stream_id,
            change_set_id: change_set.value!.target_stream.stream_id,
            source_registration:,
            policy_partition: policy_partition.value!,
            policy_head: policy_head.value!,
            decision_id: policy_head.value!.stream_id,
            routing_markers:
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, "Candidate impact scan source is invalid: #{error.message}"))
      end

      private

      def family_for(source_event, source_payload)
        if PAIR_SOURCE_TYPES.any? { source_payload.is_a?(_1) }
          return Success([ "CandidateImpactPairScan", "candidate-impact-pair-scan" ])
        end
        if REGISTRY_SOURCE_TYPES.any? { source_payload.is_a?(_1) }
          return Success([ "CandidateImpactRegistrySweep", "candidate-impact-registry-sweep" ])
        end

        Failure(inconsistent(source_event, "Unsupported Candidate impact scan contract"))
      end

      def resolve_change_set(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_id:
      )
        @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: "DevelopmentPlanning",
            stream_name: "ChangeSet",
            stream_id: source_id
          ),
          target_stream_context: "DevelopmentPlanning",
          target_stream_name: "ChangeSet",
          identity_role: "change-set"
        )
      end

      def resolve_policy_head(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_head:
      )
        target = policy_head_target(source_event, source_head.event)
        return target if target.failure?

        target_event_type, target_step_name = target.value!

        @target_event_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source_head.event,
          target_stream_context: "HumanGuidance",
          target_stream_name: "Decision",
          identity_role: "decision",
          target_event_type:,
          target_step_name:
        )
      end

      def policy_head_target(source_event, reference)
        case reference.type
        when "DecisionActivated"
          Success([ "DecisionActivated", "activate-decision" ])
        when "DecisionDefinitionCorrected"
          Success([ "DecisionDefinitionCorrected", "correct-decision-definition" ])
        else
          Failure(inconsistent(source_event, "Candidate impact scan policy head is not an active Decision fact"))
        end
      end

      def resolve_policy_partition(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_reference:,
        source_head:
      )
        source_fact = load_reference(
          source_event:,
          source_upper_position:,
          source_reference:
        )
        return source_fact if source_fact.failure?

        partition_event = source_fact.value!.payload
        unless partition_event.is_a?(Events::DecisionPartitionAdvancedV1)
          return Failure(inconsistent(source_event, "Candidate impact policy partition reference is invalid"))
        end

        target_partition = @decision_partition_identity_mapper.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          partition: partition_event.partition
        )
        return target_partition if target_partition.failure?

        membership = @decision_partition_delta_resolver.membership(
          source_event: source_fact.value!.event,
          source_upper_position:,
          source_head:
        )
        return membership if membership.failure?

        delta, target_step_name = membership.value!
        target_event_type = target_step_name == "add-decision-to-partition" ?
          "DecisionAddedToPartition" : "DecisionRemovedFromPartition"
        @target_event_reference_resolver.call_in_stream(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference: event_reference(delta.source_event),
          target_stream: StreamReference.new(
            context: "HumanGuidance",
            stream_name: "DecisionPartition",
            stream_id: target_partition.value!.partition_id
          ),
          target_event_type:,
          target_step_name:
        )
      end

      def resolve_registration(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_payload:
      )
        return Success([ nil, [] ]) unless PAIR_SOURCE_TYPES.any? { source_payload.is_a?(_1) }

        source_reference = source_payload.source_registration
        registration_fact = load_reference(source_event:, source_upper_position:, source_reference:)
        return registration_fact if registration_fact.failure?

        registration = registration_fact.value!.payload
        unless registration.is_a?(Events::CandidateImpactSurfaceRegisteredV1)
          return Failure(inconsistent(source_event, "Candidate impact scan registration reference is invalid"))
        end

        context = @candidate_context_resolver.from_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: registration.candidate_event
        )
        return context if context.failure?

        evidence = registration_evidence(
          source_event:,
          source_upper_position:,
          registration:
        )
        return evidence if evidence.failure?

        target_reference = @target_event_reference_resolver.call_in_stream(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference:,
          target_stream: context.value!.candidate_stream,
          target_event_type: "CandidateImpactSurfaceAssigned",
          target_step_name: "assign-candidate-impact-surface"
        )
        return target_reference if target_reference.failure?

        manifest, build_context, surface = evidence.value!
        markers = @index_marker_builder.counterpart_documents(
          repository_id: context.value!.repository_id,
          manifest:,
          build_context:,
          surface:,
          direction: source_payload.direction
        )
        Success([ target_reference.value!, markers ])
      end

      def registration_evidence(source_event:, source_upper_position:, registration:)
        manifest = load_reference(
          source_event:,
          source_upper_position:,
          source_reference: registration.manifest_event
        )
        return manifest if manifest.failure?

        build_context = if registration.build_context_event
          load_reference(
            source_event:,
            source_upper_position:,
            source_reference: registration.build_context_event
          )
        else
          Success(nil)
        end
        return build_context if build_context.failure?

        surface = load_reference(
          source_event:,
          source_upper_position:,
          source_reference: registration.surface_event
        )
        return surface if surface.failure?

        values = [ manifest.value!.payload, build_context.value!&.payload, surface.value!.payload ]
        valid = values.fetch(0).is_a?(Events::CandidateChangeManifestCapturedV1) &&
          (values.fetch(1).nil? || values.fetch(1).is_a?(Events::CandidateBuildContextCapturedV1)) &&
          values.fetch(2).is_a?(Events::CandidateImpactSurfaceDerivedV1)
        return Success(values) if valid

        Failure(inconsistent(source_event, "Candidate impact scan evidence references are invalid"))
      end

      def load_reference(source_event:, source_upper_position:, source_reference:)
        persisted = @event_store.read_at(stream_for(source_reference), source_reference.stream_revision)
        unless persisted && persisted.id == source_reference.event_id && persisted.type == source_reference.type &&
            persisted.global_position <= source_upper_position
          return Failure(inconsistent(source_event, "Candidate impact scan source reference is absent"))
        end

        Success(CandidateSourceFactV1.new(event: persisted, payload: load_payload(persisted)))
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, "Candidate impact scan source reference is invalid: #{error.message}"))
      end

      def load_payload(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def stream_for(reference)
        StreamReference.new(
          context: reference.stream_context,
          stream_name: reference.stream_name,
          stream_id: reference.stream_id
        )
      end

      def event_reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message:,
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
