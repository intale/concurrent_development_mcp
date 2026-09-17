# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class VerificationObligationContextResolver
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        stream_identity_allocator:,
        entity_reference_resolver:,
        candidate_subject_transformer:,
        policy_transformer:,
        partition_reference_resolver:,
        target_event_reference_resolver:,
        compound_marker_builder:,
        matcher: CandidateObligations::Matcher.new,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @entity_reference_resolver = entity_reference_resolver
        @candidate_subject_transformer = candidate_subject_transformer
        @policy_transformer = policy_transformer
        @partition_reference_resolver = partition_reference_resolver
        @target_event_reference_resolver = target_event_reference_resolver
        @compound_marker_builder = compound_marker_builder
        @matcher = matcher
        @schema_registry = schema_registry
      end

      def from_creation(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_creation:
      )
        resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          creation_event: source_event,
          source_creation:,
          include_target_reference: false
        )
      end

      def from_stream(migration_id:, source_config_name:, source_upper_position:, source_event:)
        creation_event = @event_store.read_at(stream_for(source_event), 0)
        unless creation_event && creation_event.global_position <= source_upper_position
          return Failure(inconsistent(source_event, "obligation creation is absent from the frozen source range"))
        end

        source_creation = load(creation_event)
        unless source_creation.is_a?(Events::VerificationObligationCreatedV1)
          return Failure(inconsistent(source_event, "obligation stream does not begin with VerificationObligationCreated@1"))
        end

        resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          creation_event:,
          source_creation:,
          include_target_reference: true
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def load_reference(source_event:, source_upper_position:, source_reference:)
        event = @event_store.read_at(stream_for(source_reference), source_reference.stream_revision)
        unless event && event.id == source_reference.event_id && event.type == source_reference.type &&
            event.global_position <= source_upper_position
          return Failure(inconsistent(source_event, "referenced event is absent from the frozen source range"))
        end

        Success([ event, load(event) ].freeze)
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def target_reference(
        migration_id:,
        source_upper_position:,
        source_event:,
        source_reference:,
        target_stream:,
        target_event_type:,
        target_step_name:
      )
        @target_event_reference_resolver.call_in_stream(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference:,
          target_stream:,
          target_event_type:,
          target_step_name:
        )
      end

      def partition_reference(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_reference:
      )
        @partition_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference:
        )
      end

      private

      def resolve(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        creation_event:,
        source_creation:,
        include_target_reference:
      )
        physical = validate_physical_creation(
          source_event:,
          creation_event:,
          source_creation:,
          source_upper_position:
        )
        return physical if physical.failure?

        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event: creation_event,
          target_stream_context: "DevelopmentIntegration",
          target_stream_name: "VerificationObligation",
          identity_role: "verification-obligation"
        )
        return allocation if allocation.failure?

        change_set = resolve_change_set(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_creation:
        )
        return change_set if change_set.failure?

        source_candidate = transform_subject(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          subject: source_creation.source_candidate
        )
        return source_candidate if source_candidate.failure?

        target_candidate = transform_subject(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          subject: source_creation.target_candidate
        )
        return target_candidate if target_candidate.failure?

        target_change_set_id = change_set.value!.target_stream.stream_id
        policy = @policy_transformer.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          policy: source_creation.policy,
          source_change_set_id: source_creation.change_set_id,
          target_change_set_id:
        )
        return policy if policy.failure?

        semantic = validate_semantics(
          source_event:,
          source_creation:,
          source_candidate: source_candidate.value!,
          target_candidate: target_candidate.value!
        )
        return semantic if semantic.failure?

        target_stream = allocation.value!.target_stream
        target_creation_event = if include_target_reference
          mapped = target_reference(
            migration_id:,
            source_upper_position:,
            source_event:,
            source_reference: reference_for(creation_event),
            target_stream:,
            target_event_type: "VerificationObligationCreated",
            target_step_name: "create-verification-obligation"
          )
          return mapped if mapped.failure?

          mapped.value!
        end

        Success(
          VerificationObligationContextV1.new(
            source_creation:,
            source_creation_event: creation_event,
            target_creation_event:,
            target_stream:,
            obligation_id: target_stream.stream_id,
            change_set_id: target_change_set_id,
            source_candidate: source_candidate.value!,
            target_candidate: target_candidate.value!,
            policy: policy.value!,
            natural_key_marker: natural_key_marker(
              source_candidate.value!.target_subject,
              target_candidate.value!.target_subject,
              policy.value!,
              source_creation.rule_version
            )
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def validate_physical_creation(source_event:, creation_event:, source_creation:, source_upper_position:)
        stream = stream_for(creation_event)
        valid = creation_event.type == "VerificationObligationCreated" &&
                creation_event.metadata.fetch("schema_version") == 1 &&
                creation_event.global_position <= source_upper_position &&
                creation_event.stream_revision.zero? &&
                stream.context == "DevelopmentIntegration" &&
                stream.stream_name == "VerificationObligation" &&
                stream.stream_id == source_creation.obligation_id &&
                creation_event.markers.include?("verification-obligation:#{source_creation.obligation_id}") &&
                source_creation.status == "open"
        return Success() if valid

        Failure(inconsistent(source_event, "obligation identity, schema, stream, revision, marker, or status is invalid"))
      end

      def validate_semantics(source_event:, source_creation:, source_candidate:, target_candidate:)
        source_subject = source_candidate.source_subject
        target_subject = target_candidate.source_subject
        valid = source_subject.change_set_id == source_creation.change_set_id &&
                target_subject.change_set_id == source_creation.change_set_id &&
                source_subject.candidate_id != target_subject.candidate_id &&
                source_creation.policy.required_evidence == source_creation.required_evidence &&
                source_creation.policy.enforcement == source_creation.enforcement &&
                @matcher.call(
                  source: source_candidate.source_evidence,
                  target: target_candidate.source_evidence
                ) == source_creation.reasons
        return Success() if valid

        Failure(inconsistent(source_event, "obligation definition disagrees with Candidate or policy evidence"))
      end

      def resolve_change_set(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_creation:
      )
        @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: "DevelopmentPlanning",
            stream_name: "ChangeSet",
            stream_id: source_creation.change_set_id
          ),
          target_stream_context: "DevelopmentPlanning",
          target_stream_name: "ChangeSet",
          identity_role: "change-set"
        )
      end

      def transform_subject(**arguments)
        @candidate_subject_transformer.call(**arguments)
      end

      def natural_key_marker(source, target, policy, rule_version)
        @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "candidate-compatibility-obligation",
            components: [
              "source-surface-event:#{source.surface_event.event_id}",
              "target-surface-event:#{target.surface_event.event_id}",
              "policy-partition-event:#{policy.partition_event.event_id}",
              "policy-head-event:#{policy.head.event.event_id}",
              "rule-version:#{rule_version}"
            ]
          )
        ).marker
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def stream_for(value)
        stream = value.respond_to?(:stream) ? value.stream : value
        StreamReference.new(
          context: stream.respond_to?(:context) ? stream.context : stream.stream_context,
          stream_name: stream.stream_name,
          stream_id: stream.stream_id
        )
      end

      def reference_for(event)
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
          message: "Verification obligation migration is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
