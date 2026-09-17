# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MergeAuthorizationDocumentTransformer
      include Dry::Monads[:result]

      ENTITY_TARGETS = {
        change_set: [ "DevelopmentPlanning", "ChangeSet", "change-set" ],
        work_item: [ "DevelopmentExecution", "WorkItem", "work-item" ],
        attempt: [ "DevelopmentExecution", "Attempt", "attempt" ],
        repository: [ "DevelopmentPlanning", "Repository", "repository" ],
        candidate: [ "DevelopmentIntegration", "Candidate", "candidate" ],
        merge_verification: [ "DevelopmentIntegration", "MergeVerification", "merge-verification" ],
        verification_obligation: [
          "DevelopmentIntegration", "VerificationObligation", "verification-obligation"
        ]
      }.freeze

      def initialize(
        entity_reference_resolver:,
        reference_resolver:,
        partition_identity_mapper:,
        head_reference_resolver:,
        marked_event_locator:,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @entity_reference_resolver = entity_reference_resolver
        @reference_resolver = reference_resolver
        @partition_identity_mapper = partition_identity_mapper
        @head_reference_resolver = head_reference_resolver
        @marked_event_locator = marked_event_locator
        @schema_registry = schema_registry
      end

      def snapshot_binding(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        context:,
        binding:
      )
        verified = @reference_resolver.load_reference(
          source_event:,
          source_upper_position:,
          source_reference: binding.verification_event
        )
        return verified if verified.failure?

        verified_payload = verified.value!.last
        unless binding.registration_event == context.source_registration_reference &&
            binding.snapshot_digest == context.source_registration.snapshot_digest &&
            verified_payload.is_a?(Events::MergeSnapshotVerifiedV1) &&
            verified_payload.merge_snapshot_id == context.source_registration.merge_snapshot_id &&
            verified_payload.verification_digest == binding.verification_digest
          return Failure(inconsistent(source_event, "snapshot binding disagrees with its source facts"))
        end

        target_verification = resolve_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: binding.verification_event
        )
        return target_verification if target_verification.failure?
        unless target_verification.value!.stream_id == context.merge_snapshot_id
          return Failure(inconsistent(source_event, "snapshot verification mapped to another MergeSnapshot"))
        end

        Success(
          MergeAuthorizations::SnapshotBindingV1.new(
            registration_event: context.target_registration_event!,
            snapshot_digest: binding.snapshot_digest,
            verification_event: target_verification.value!,
            verification_digest: binding.verification_digest
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def expected_impact_policy(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        policy:
      )
        return Success(nil) unless policy

        partition_event = resolve_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: policy.partition_event
        )
        return partition_event if partition_event.failure?

        head = @head_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          head: policy.head
        )
        return head if head.failure?

        Success(
          MergeAuthorizations::ExpectedImpactPolicyV1.new(
            partition_event: partition_event.value!,
            head: head.value!,
            definition_digest: policy.definition_digest
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def evaluation(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        context:,
        evaluation:
      )
        common = {
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:
        }
        unless evaluation.merge_snapshot_id == context.source_registration.merge_snapshot_id
          return Failure(inconsistent(source_event, "evaluation identifies another MergeSnapshot"))
        end

        snapshot = transform_snapshot(**common, context:, snapshot: evaluation.snapshot)
        return snapshot if snapshot.failure?

        target_base = transform_target_base(
          **common,
          context:,
          observation: evaluation.target_base_observation
        )
        return target_base if target_base.failure?

        current_policy = transform_current_policy(**common, policy: evaluation.current_policy)
        return current_policy if current_policy.failure?

        candidates = transform_many(evaluation.candidates) do |candidate|
          transform_candidate(**common, context:, candidate:)
        end
        return candidates if candidates.failure?

        progress = transform_many(evaluation.work_item_progress) do |entry|
          transform_work_item_progress(**common, context:, progress: entry)
        end
        return progress if progress.failure?

        obligations = transform_many(evaluation.obligations) do |obligation|
          transform_obligation(**common, obligation:)
        end
        return obligations if obligations.failure?

        reasons = transform_many(evaluation.reasons) do |reason|
          transform_reason(**common, reason:)
        end
        return reasons if reasons.failure?

        Success(
          MergeAuthorizations::EvaluationV1.new(
            merge_snapshot_id: context.merge_snapshot_id,
            snapshot: snapshot.value!,
            target_base_observation: target_base.value!,
            current_policy: current_policy.value!,
            candidates: candidates.value!,
            work_item_progress: progress.value!,
            obligations: obligations.value!,
            reasons: reasons.value!
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def transform_snapshot(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        context:,
        snapshot:
      )
        return Success(nil) unless snapshot
        unless snapshot.registration_event == context.source_registration_reference &&
            context.source_state_matches?(snapshot.registration)
          return Failure(inconsistent(source_event, "evaluation snapshot registration is inconsistent"))
        end

        verification = transform_verified_observation(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          context:,
          verification: snapshot.verification
        )
        return verification if verification.failure?

        verification_event = if snapshot.verification_event
          resolved = resolve_reference(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_reference: snapshot.verification_event
          )
          return resolved if resolved.failure?

          resolved.value!
        end
        if verification.value!.nil? != verification_event.nil?
          return Failure(inconsistent(source_event, "evaluation verification evidence is incomplete"))
        end
        if verification.value! && verification_event != verification.value!.verified_event
          return Failure(inconsistent(source_event, "evaluation verification references disagree"))
        end

        Success(
          MergeAuthorizations::SnapshotEvidenceV1.new(
            registration: context.target_state(snapshot_digest: snapshot.registration.snapshot_digest),
            registration_event: context.target_registration_event!,
            verification: verification.value!,
            verification_event:
          )
        )
      end

      def transform_verified_observation(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        context:,
        verification:
      )
        return Success(nil) unless verification
        source_snapshot_id = context.source_registration.merge_snapshot_id
        unless verification.selected.merge_snapshot_id == source_snapshot_id &&
            verification.verified.merge_snapshot_id == source_snapshot_id
          return Failure(inconsistent(source_event, "evaluation verification identifies another MergeSnapshot"))
        end

        verification_id = resolve_entity_id(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          kind: :merge_verification,
          source_id: verification.selected.verification_id
        )
        return verification_id if verification_id.failure?

        selected_event = resolve_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: verification.selected_event
        )
        return selected_event if selected_event.failure?

        verified_event = resolve_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: verification.verified_event
        )
        return verified_event if verified_event.failure?

        Success(
          MergeSnapshotVerifications::VerifiedObservationV2.new(
            selected: Events::MergeSnapshotVerificationSelectedV1.new(
              merge_snapshot_id: context.merge_snapshot_id,
              verification_id: verification_id.value!
            ),
            selected_event: selected_event.value!,
            verified: Events::MergeSnapshotVerifiedV2.new(
              merge_snapshot_id: context.merge_snapshot_id
            ),
            verified_event: verified_event.value!,
            policy_version: verification.policy_version,
            verification_digest: verification.verification_digest
          )
        )
      end

      def transform_target_base(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        context:,
        observation:
      )
        unless observation.repository_id == context.source_registration.repository_id &&
            observation.target_branch == context.source_registration.target_branch &&
            observation.object_format == context.source_registration.object_format
          return Failure(inconsistent(source_event, "target-base observation has another repository scope"))
        end

        repository_id = resolve_entity_id(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          kind: :repository,
          source_id: observation.repository_id
        )
        return repository_id if repository_id.failure?
        unless repository_id.value! == context.repository_id
          return Failure(inconsistent(source_event, "target-base repository mapping is inconsistent"))
        end

        Success(
          MergeAuthorizations::TargetBaseObservationV1.new(
            observation.to_h.merge(repository_id: repository_id.value!)
          )
        )
      end

      def transform_current_policy(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        policy:
      )
        return Success(nil) unless policy

        partition = @partition_identity_mapper.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          partition: policy.partition
        )
        return partition if partition.failure?

        partition_event = transform_optional(policy.partition_event) do |reference|
          resolve_reference(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_reference: reference
          )
        end
        return partition_event if partition_event.failure?

        head = transform_optional(policy.head) do |value|
          @head_reference_resolver.call(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            head: value
          )
        end
        return head if head.failure?

        Success(
          MergeAuthorizations::CurrentImpactPolicyV1.new(
            policy.to_h.merge(
              partition: partition.value!,
              partition_event: partition_event.value!,
              head: head.value!
            )
          )
        )
      end

      def transform_candidate(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        context:,
        candidate:
      )
        candidate_context = candidate_context(context, candidate.candidate_id)
        return Failure(inconsistent(source_event, "evaluation Candidate is outside the MergeSnapshot")) unless
          candidate_context

        references = {}
        %i[candidate_event manifest_event surface_event surface_registration_event].each do |attribute|
          resolved = resolve_reference(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_reference: candidate.public_send(attribute)
          )
          return resolved if resolved.failure?

          references[attribute] = resolved.value!
        end
        unless references.fetch(:candidate_event).stream_id == candidate_context.candidate_id
          return Failure(inconsistent(source_event, "evaluation Candidate mapping is inconsistent"))
        end

        Success(
          MergeAuthorizations::CandidateEvidenceReferenceV1.new(
            candidate.to_h.merge(candidate_id: candidate_context.candidate_id, **references)
          )
        )
      end

      def transform_work_item_progress(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        context:,
        progress:
      )
        candidate = candidate_context(context, progress.candidate_id)
        unless candidate && [
          progress.change_set_id,
          progress.work_item_id,
          progress.repository_id,
          progress.attempt_id,
          progress.candidate_id
        ] == [
          candidate.source_candidate.change_set_id,
          candidate.source_candidate.work_item_id,
          candidate.source_candidate.repository_id,
          candidate.source_candidate.attempt_id,
          candidate.source_candidate.candidate_id
        ]
          return Failure(inconsistent(source_event, "WorkItem progress disagrees with its Candidate"))
        end

        candidate_event = resolve_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: progress.candidate_event
        )
        return candidate_event if candidate_event.failure?
        selected_event = resolve_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: progress.selected_event
        )
        return selected_event if selected_event.failure?
        completed_event = resolve_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: progress.completed_event
        )
        return completed_event if completed_event.failure?

        dependencies = transform_many(progress.incoming_dependencies) do |dependency|
          transform_dependency_progress(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            dependency:
          )
        end
        return dependencies if dependencies.failure?

        Success(
          MergeAuthorizations::WorkItemProgressV1.new(
            change_set_id: candidate.change_set_id,
            work_item_id: candidate.work_item_id,
            repository_id: candidate.repository_id,
            attempt_id: candidate.attempt_id,
            candidate_id: candidate.candidate_id,
            candidate_event: candidate_event.value!,
            selected_event: selected_event.value!,
            completed_event: completed_event.value!,
            incoming_dependencies: dependencies.value!
          )
        )
      end

      def transform_dependency_progress(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        dependency:
      )
        dependency_id = resolve_dependency_id(
          source_event:,
          source_upper_position:,
          source_dependency_id: dependency.dependency_id
        )
        return dependency_id if dependency_id.failure?

        satisfaction = resolve_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: dependency.satisfaction_event
        )
        return satisfaction if satisfaction.failure?
        source = resolve_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: dependency.source_event
        )
        return source if source.failure?

        Success(
          MergeAuthorizations::DependencyProgressV1.new(
            dependency_id: dependency_id.value!,
            satisfaction_event: satisfaction.value!,
            source_event: source.value!
          )
        )
      end

      def transform_obligation(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        obligation:
      )
        source_candidate = resolve_entity_id(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          kind: :candidate,
          source_id: obligation.source_candidate_id
        )
        return source_candidate if source_candidate.failure?
        target_candidate = resolve_entity_id(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          kind: :candidate,
          source_id: obligation.target_candidate_id
        )
        return target_candidate if target_candidate.failure?

        creation = transform_optional(obligation.creation_event) do |reference|
          resolve_reference(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_reference: reference
          )
        end
        return creation if creation.failure?
        terminal = transform_optional(obligation.terminal_event) do |reference|
          resolve_reference(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_reference: reference
          )
        end
        return terminal if terminal.failure?

        obligation_id = resolve_optional_entity_id(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          kind: :verification_obligation,
          source_id: obligation.obligation_id
        )
        return obligation_id if obligation_id.failure?
        if creation.value! && creation.value!.stream_id != obligation_id.value!
          return Failure(inconsistent(source_event, "obligation identity and creation reference disagree"))
        end

        Success(
          MergeAuthorizations::ObligationCheckV1.new(
            obligation.to_h.merge(
              obligation_id: obligation_id.value!,
              source_candidate_id: source_candidate.value!,
              target_candidate_id: target_candidate.value!,
              creation_event: creation.value!,
              terminal_event: terminal.value!
            )
          )
        )
      end

      def transform_reason(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        reason:
      )
        common = {
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:
        }
        values = reason.to_h
        {
          candidate_id: :candidate,
          source_candidate_id: :candidate,
          target_candidate_id: :candidate,
          work_item_id: :work_item,
          obligation_id: :verification_obligation
        }.each do |attribute, kind|
          resolved = resolve_optional_entity_id(
            **common,
            kind:,
            source_id: reason.public_send(attribute)
          )
          return resolved if resolved.failure?

          values[attribute] = resolved.value!
        end
        if reason.dependency_id
          dependency = resolve_dependency_id(
            source_event:,
            source_upper_position:,
            source_dependency_id: reason.dependency_id
          )
          return dependency if dependency.failure?

          values[:dependency_id] = dependency.value!
        end
        %i[expected_reference observed_reference].each do |attribute|
          reference = reason.public_send(attribute)
          next unless reference

          resolved = resolve_reference(**common, source_reference: reference)
          return resolved if resolved.failure?

          values[attribute] = resolved.value!
        end
        Success(MergeAuthorizations::ReasonV1.new(values))
      end

      def resolve_dependency_id(source_event:, source_upper_position:, source_dependency_id:)
        declaration = @marked_event_locator.call(
          source_event:,
          source_upper_position:,
          stream_context: "DevelopmentPlanning",
          stream_name: "ChangeSet",
          event_type: "WorkItemDependencyDeclared",
          marker: "dependency:#{source_dependency_id}"
        )
        return declaration if declaration.failure?

        payload = load(declaration.value!)
        unless payload.is_a?(Events::WorkItemDependencyDeclaredV1) &&
            payload.dependency_id == source_dependency_id
          return Failure(inconsistent(source_event, "dependency identity is inconsistent"))
        end

        Success(declaration.value!.id)
      end

      def resolve_optional_entity_id(**context)
        return Success(nil) unless context.fetch(:source_id)

        resolve_entity_id(**context)
      end

      def resolve_entity_id(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        kind:,
        source_id:
      )
        target = ENTITY_TARGETS.fetch(kind)
        allocation = @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: target.fetch(0),
            stream_name: target.fetch(1),
            stream_id: source_id
          ),
          target_stream_context: target.fetch(0),
          target_stream_name: target.fetch(1),
          identity_role: target.fetch(2)
        )
        return allocation if allocation.failure?

        Success(allocation.value!.target_stream.stream_id)
      end

      def resolve_reference(**context)
        @reference_resolver.call(**context)
      end

      def candidate_context(context, source_candidate_id)
        context.candidate_contexts.find do |candidate|
          candidate.source_candidate.candidate_id == source_candidate_id
        end
      end

      def transform_many(values)
        transformed = []
        values.each do |value|
          result = yield(value)
          return result if result.failure?

          transformed << result.value!
        end
        Success(transformed.freeze)
      end

      def transform_optional(value)
        return Success(nil) unless value

        yield(value)
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
          message: "Merge authorization document is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
