# frozen_string_literal: true

module Coordinator::Write
  module MergeAuthorizations
    class Evaluator
      RULE_VERSION = "candidate-compatibility-obligation/v1"

      def initialize(
        event_store:,
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new,
        candidate_loader: CandidateObligations::CandidateEvidenceLoader.new(event_store:),
        definition_loader: CandidateObligations::DecisionDefinitionLoader.new(event_store:),
        matcher: CandidateObligations::Matcher.new,
        natural_key_builder: CandidateObligations::NaturalKeyBuilder.new,
        obligation_loader: CandidateObligations::ObligationLoader.new(event_store:),
        validity_builder: CandidateObligations::ValidityBuilder.new,
        canonical_json: CanonicalJson.new,
        policy_contract: Contracts::CandidateImpactPolicyDefinition.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
        @candidate_loader = candidate_loader
        @definition_loader = definition_loader
        @matcher = matcher
        @natural_key_builder = natural_key_builder
        @obligation_loader = obligation_loader
        @validity_builder = validity_builder
        @canonical_json = canonical_json
        @policy_contract = policy_contract
      end

      def call(command, decided_at:)
        reasons = []
        snapshot = load_snapshot(command, reasons)
        return evaluation(command, snapshot:, current_policy: nil, candidates: [], work_item_progress: [], obligations: [], reasons:) unless snapshot

        validate_snapshot_binding(command, snapshot, reasons)
        validate_target_base(command, snapshot.registration, reasons)
        change_set_id = change_set_id(snapshot.registration, reasons)
        return evaluation(command, snapshot:, current_policy: nil, candidates: [], work_item_progress: [], obligations: [], reasons:) unless change_set_id

        work_item_progress = load_work_item_progress(snapshot.registration, change_set_id, reasons)

        current_policy = load_current_policy(change_set_id, decided_at:)
        unless expected_policy_matches?(command.expected_impact_policy, current_policy)
          reasons << reason(
            code: "impact_policy_context_stale",
            message: "Expected Candidate-impact policy context is not current",
            expected_reference: command.expected_impact_policy&.partition_event,
            observed_reference: current_policy.partition_event,
            expected_digest: command.expected_impact_policy&.definition_digest,
            observed_digest: current_policy.definition_digest
          )
        end
        unless reasons.empty?
          return evaluation(command, snapshot:, current_policy:, candidates: [], work_item_progress:, obligations: [], reasons:)
        end
        unless current_policy.gating?
          return evaluation(command, snapshot:, current_policy:, candidates: [], work_item_progress:, obligations: [], reasons:)
        end

        candidate_evidence, candidate_references = load_candidate_surfaces(
          snapshot.registration,
          change_set_id,
          reasons
        )
        obligations = if reasons.empty?
                        evaluate_obligations(candidate_evidence, current_policy, change_set_id, reasons)
        else
                        []
        end
        evaluation(
          command,
          snapshot:,
          current_policy:,
          candidates: candidate_references,
          work_item_progress:,
          obligations:,
          reasons:
        )
      end

      private

      def load_snapshot(command, reasons)
        stream = @stream_factory.merge_snapshot(command.merge_snapshot_id)
        registration_event = @event_store.read(stream, EventQueries::MERGE_SNAPSHOT_REGISTRATION).first
        unless registration_event
          reasons << reason(
            code: "merge_snapshot_not_found",
            message: "Merge snapshot does not exist",
            expected_reference: command.snapshot_binding.registration_event
          )
          return
        end
        verification_event = @event_store.read(stream, EventQueries::MERGE_SNAPSHOT_VERIFIED).first
        SnapshotEvidenceV1.new(
          registration: load_event(registration_event),
          registration_event: event_reference(registration_event),
          verification: verification_event && load_event(verification_event),
          verification_event: verification_event && event_reference(verification_event)
        )
      end

      def validate_snapshot_binding(command, snapshot, reasons)
        binding = command.snapshot_binding
        registration = snapshot.registration
        unless binding.registration_event == snapshot.registration_event &&
               binding.snapshot_digest == registration.snapshot_digest
          reasons << reason(
            code: "merge_snapshot_binding_stale",
            message: "Registration binding is not current for this immutable snapshot",
            expected_reference: binding.registration_event,
            observed_reference: snapshot.registration_event,
            expected_digest: binding.snapshot_digest,
            observed_digest: registration.snapshot_digest
          )
        end
        unless snapshot.verification
          reasons << reason(
            code: "merge_snapshot_not_verified",
            message: "Exact merge snapshot verification is required",
            expected_reference: binding.verification_event,
            expected_digest: binding.verification_digest
          )
          return
        end
        return if binding.verification_event == snapshot.verification_event &&
                  binding.verification_digest == snapshot.verification.verification_digest

        reasons << reason(
          code: "merge_snapshot_binding_stale",
          message: "Verification binding is not current for this immutable snapshot",
          expected_reference: binding.verification_event,
          observed_reference: snapshot.verification_event,
          expected_digest: binding.verification_digest,
          observed_digest: snapshot.verification.verification_digest
        )
      end

      def validate_target_base(command, registration, reasons)
        observation = command.target_base_observation
        same_scope = observation.repository_id == registration.repository_id &&
                     observation.target_branch == registration.target_branch &&
                     observation.object_format == registration.object_format
        return if same_scope && observation.commit_oid == registration.target_base_commit_oid

        reasons << reason(
          code: "target_base_binding_stale",
          message: "Observed target base does not match the registered merge snapshot",
          expected_oid: registration.target_base_commit_oid,
          observed_oid: observation.commit_oid
        )
      end

      def change_set_id(registration, reasons)
        ids = registration.ordered_candidates.map(&:change_set_id).uniq
        return ids.sole if ids.one?

        reasons << reason(
          code: "mixed_change_set_snapshot",
          message: "Version 1 authorizes Candidates from exactly one ChangeSet"
        )
        nil
      end

      def load_work_item_progress(registration, change_set_id, reasons)
        change_set_events = @event_store.read(
          @stream_factory.change_set(change_set_id),
          EventQueries::CHANGE_SET_FOR_MERGE_AUTHORIZATION
        )
        change_set_state = Domain::ChangeSets::State.reduce(change_set_events.map { load_event(_1) })
        satisfactions = change_set_events.filter_map do |event|
          next unless event.type == "WorkItemDependencySatisfied"

          payload = load_event(event)
          [ payload.dependency_id, [ payload, event_reference(event) ] ]
        end.to_h

        registration.ordered_candidates.filter_map do |candidate|
          reason_count = reasons.length
          unless change_set_state.work_item_ids.include?(candidate.work_item_id)
            reasons << reason(
              code: "candidate_work_item_not_member",
              message: "Snapshot Candidate WorkItem is not a frozen ChangeSet member",
              candidate_id: candidate.candidate_id,
              work_item_id: candidate.work_item_id
            )
            next
          end

          events = @event_store.read(
            @stream_factory.work_item(candidate.work_item_id),
            EventQueries::WORK_ITEM_FOR_MERGE_AUTHORIZATION
          ).to_h { [ _1.type, _1 ] }
          created_event = events["WorkItemCreated"]
          selected_event = events["WorkItemCandidateSelected"]
          completed_event = events["WorkItemCompleted"]
          created = created_event && load_event(created_event)
          selected = selected_event && load_event(selected_event)
          completed = completed_event && load_event(completed_event)

          validate_work_item_scope(created, candidate, change_set_id, reasons)
          validate_selection(selected, selected_event, candidate, reasons)
          validate_completion(completed, completed_event, candidate, reasons)
          incoming = dependency_progress(
            change_set_state,
            satisfactions,
            candidate,
            reasons
          )
          next unless reasons.length == reason_count

          WorkItemProgressV1.new(
            change_set_id:,
            work_item_id: candidate.work_item_id,
            repository_id: candidate.repository_id,
            attempt_id: candidate.attempt_id,
            candidate_id: candidate.candidate_id,
            candidate_event: candidate.candidate_event,
            selected_event: event_reference(selected_event),
            completed_event: event_reference(completed_event),
            incoming_dependencies: incoming
          )
        end.freeze
      end

      def validate_work_item_scope(created, candidate, change_set_id, reasons)
        return if created.is_a?(Events::WorkItemCreatedV1) &&
                  created.change_set_id == change_set_id &&
                  created.work_item_id == candidate.work_item_id &&
                  created.repository_id == candidate.repository_id

        reasons << reason(
          code: "candidate_work_item_scope_invalid",
          message: "Snapshot Candidate WorkItem scope does not match authoritative history",
          candidate_id: candidate.candidate_id,
          work_item_id: candidate.work_item_id
        )
      end

      def validate_selection(selected, selected_event, candidate, reasons)
        unless selected
          reasons << reason(
            code: "candidate_not_selected",
            message: "Snapshot Candidate has not been selected by its WorkItem",
            candidate_id: candidate.candidate_id,
            work_item_id: candidate.work_item_id,
            expected_reference: candidate.candidate_event
          )
          return
        end
        return if selected.is_a?(Events::WorkItemCandidateSelectedV1) &&
                  selected.change_set_id == candidate.change_set_id &&
                  selected.work_item_id == candidate.work_item_id &&
                  selected.attempt_id == candidate.attempt_id &&
                  selected.candidate_id == candidate.candidate_id &&
                  selected.candidate_event == candidate.candidate_event

        reasons << reason(
          code: "candidate_selection_mismatch",
          message: "WorkItem selected a different Candidate or Attempt",
          candidate_id: candidate.candidate_id,
          work_item_id: candidate.work_item_id,
          expected_reference: candidate.candidate_event,
          observed_reference: selected_event && event_reference(selected_event)
        )
      end

      def validate_completion(completed, completed_event, candidate, reasons)
        unless completed
          reasons << reason(
            code: "candidate_work_item_not_completed",
            message: "Snapshot Candidate WorkItem has not completed",
            candidate_id: candidate.candidate_id,
            work_item_id: candidate.work_item_id
          )
          return
        end
        return if completed.is_a?(Events::WorkItemCompletedV1) &&
                  completed.change_set_id == candidate.change_set_id &&
                  completed.work_item_id == candidate.work_item_id &&
                  completed.attempt_id == candidate.attempt_id &&
                  completed.candidate_id == candidate.candidate_id &&
                  completed.candidate_event == candidate.candidate_event

        reasons << reason(
          code: "candidate_completion_mismatch",
          message: "WorkItem completed with a different Candidate or Attempt",
          candidate_id: candidate.candidate_id,
          work_item_id: candidate.work_item_id,
          observed_reference: completed_event && event_reference(completed_event)
        )
      end

      def dependency_progress(change_set_state, satisfactions, candidate, reasons)
        change_set_state.dependencies.filter_map do |dependency|
          next unless dependency.consumer_work_item_id == candidate.work_item_id

          satisfaction = satisfactions[dependency.dependency_id]
          unless satisfaction
            reasons << reason(
              code: "candidate_dependency_unsatisfied",
              message: "Snapshot Candidate WorkItem has an unsatisfied incoming dependency",
              candidate_id: candidate.candidate_id,
              work_item_id: candidate.work_item_id,
              dependency_id: dependency.dependency_id
            )
            next
          end
          payload, reference = satisfaction
          DependencyProgressV1.new(
            dependency_id: dependency.dependency_id,
            satisfaction_event: reference,
            source_event: payload.source_event
          )
        end.freeze
      end

      def load_current_policy(change_set_id, decided_at:)
        partition = Decisions::DecisionPartitionV1.new(
          partition_id: "changeset:#{change_set_id}:candidate",
          topic_root: "candidate",
          anchor_kind: "changeset",
          anchor_id: change_set_id
        )
        event = @event_store.read_grouped(
          @stream_factory.decision_partition(partition.partition_id),
          EventQueries::DECISION_PARTITION_LATEST
        ).first
        return absent_policy(partition) unless event

        payload = load_event(event)
        reference = event_reference(event)
        valid = payload.is_a?(Events::DecisionPartitionAdvancedV1) &&
                payload.partition == partition && payload.partition_revision == event.stream_revision &&
                payload.active_decisions.include?(payload.decision)
        return invalid_policy(partition, reference) unless valid

        definitions = payload.active_decisions.map do |head|
          [ head, @definition_loader.call(head:, partition:) ]
        end
        policies = definitions.select { _2.document.topic.topic_id == "candidate.impact_policy" }
        return absent_policy(partition) if policies.empty?
        return invalid_policy(partition, reference) unless policies.one?

        head, definition = policies.sole
        expected_digest = @canonical_json.sha256(definition.document.to_h)
        validation = @policy_contract.call(
          definition:,
          change_set_id:,
          expected_digest:
        )
        return invalid_policy(partition, reference) if validation.failure?
        return invalid_policy(partition, reference) if definition.document.validity.valid_from > decided_at

        CurrentImpactPolicyV1.new(
          partition:,
          partition_event: reference,
          head:,
          definition_digest: definition.digest,
          status: definition.document.enforcement.level,
          required_evidence: definition.document.value.items,
          valid_from: definition.document.validity.valid_from
        )
      end

      def absent_policy(partition)
        CurrentImpactPolicyV1.new(
          partition:,
          partition_event: nil,
          head: nil,
          definition_digest: nil,
          status: "absent",
          required_evidence: [],
          valid_from: nil
        )
      end

      def invalid_policy(partition, reference)
        CurrentImpactPolicyV1.new(
          partition:,
          partition_event: reference,
          head: nil,
          definition_digest: nil,
          status: "absent",
          required_evidence: [],
          valid_from: nil
        )
      end

      def expected_policy_matches?(expected, current)
        if current.partition_event.nil?
          expected.nil?
        else
          expected && expected.partition_event == current.partition_event &&
            expected.head == current.head && expected.definition_digest == current.definition_digest
        end
      end

      def load_candidate_surfaces(registration, change_set_id, reasons)
        evidence = []
        references = []
        registration.ordered_candidates.each do |member|
          events = @event_store.read_marked(
            @stream_factory.candidate_impact_registry(change_set_id),
            EventQueries.candidate_impact_surface_registration("candidate:#{member.candidate_id}")
          )
          if events.empty?
            reasons << reason(
              code: "candidate_impact_surface_missing",
              message: "Gating policy requires exact Candidate impact-surface evidence",
              candidate_id: member.candidate_id
            )
            next
          end
          persisted = events.sole
          candidate = @candidate_loader.call(event_reference(persisted))
          unless candidate_matches_member?(candidate, member)
            reasons << reason(
              code: "authorization_history_invalid",
              message: "Candidate surface evidence does not match the registered snapshot member",
              candidate_id: member.candidate_id
            )
            next
          end
          evidence << candidate
          references << CandidateEvidenceReferenceV1.new(
            candidate_id: member.candidate_id,
            candidate_event: candidate.subject.candidate_event,
            manifest_event: candidate.subject.manifest_event,
            surface_event: candidate.subject.surface_event,
            surface_registration_event: candidate.subject.registration_event,
            surface_digest: candidate.subject.surface_digest
          )
        end
        [ evidence.freeze, references.freeze ]
      end

      def candidate_matches_member?(evidence, member)
        subject = evidence.subject
        subject.candidate_id == member.candidate_id &&
          subject.change_set_id == member.change_set_id &&
          subject.work_item_id == member.work_item_id &&
          subject.attempt_id == member.attempt_id &&
          subject.repository_id == member.repository_id &&
          subject.target_branch == member.target_branch &&
          subject.object_format == member.object_format &&
          subject.base_commit_oid == member.base_commit_oid &&
          subject.head_commit_oid == member.head_commit_oid &&
          subject.manifest_digest == member.manifest_digest &&
          subject.candidate_event == member.candidate_event &&
          subject.manifest_event == member.manifest_event
      end

      def evaluate_obligations(candidates, current_policy, change_set_id, reasons)
        policy = gating_policy_evidence(current_policy, change_set_id)
        checks = []
        candidates.each do |source|
          candidates.each do |target|
            next if source.subject.candidate_id == target.subject.candidate_id

            impact_reasons = @matcher.call(source:, target:)
            next if impact_reasons.empty?

            natural_key = @natural_key_builder.call(
              source:,
              target:,
              policy_partition_event: current_policy.partition_event,
              policy_head: current_policy.head,
              rule_version: RULE_VERSION
            )
            check = load_obligation_check(
              natural_key:,
              source:,
              target:,
              impact_reasons:,
              policy:
            )
            checks << check
            append_obligation_reason(reasons, check)
          end
        end
        checks.freeze
      end

      def gating_policy_evidence(current, change_set_id)
        CandidateObligations::ImpactPolicyEvidenceV1.new(
          partition_event: current.partition_event,
          partition: current.partition,
          head: current.head,
          definition_digest: current.definition_digest,
          change_set_id:,
          required_evidence: current.required_evidence,
          enforcement: current.status,
          valid_from: current.valid_from
        )
      end

      def load_obligation_check(natural_key:, source:, target:, impact_reasons:, policy:)
        persisted_creation = @obligation_loader.find(natural_key)
        return missing_obligation(natural_key, source, target, policy) unless persisted_creation

        obligation_id = persisted_creation.payload.obligation_id
        grouped = @event_store.read_grouped(
          @stream_factory.verification_obligation(obligation_id),
          EventQueries::VERIFICATION_OBLIGATION_LIFECYCLE
        ).to_h { [ _1.type, _1 ] }
        creation_event = grouped["VerificationObligationCreated"]
        return missing_obligation(natural_key, source, target, policy) unless creation_event

        creation = load_event(creation_event)
        expected_validity = @validity_builder.call(
          source:,
          target:,
          reasons: impact_reasons,
          policy:,
          rule_version: RULE_VERSION
        )
        unless valid_creation?(creation, obligation_id, source, target, policy, expected_validity.digest)
          return invalid_obligation(natural_key, obligation_id, source, target, policy, event_reference(creation_event))
        end

        status, terminal = obligation_status(grouped)
        ObligationCheckV1.new(
          obligation_id:,
          source_candidate_id: source.subject.candidate_id,
          target_candidate_id: target.subject.candidate_id,
          enforcement: policy.enforcement,
          required_evidence: policy.required_evidence,
          identity_digest: natural_key.digest,
          status:,
          validity_input_digest: creation.validity_input_digest,
          creation_event: event_reference(creation_event),
          terminal_event: terminal && event_reference(terminal)
        )
      end

      def missing_obligation(natural_key, source, target, policy)
        ObligationCheckV1.new(
          obligation_id: nil,
          source_candidate_id: source.subject.candidate_id,
          target_candidate_id: target.subject.candidate_id,
          enforcement: policy.enforcement,
          required_evidence: policy.required_evidence,
          identity_digest: natural_key.digest,
          status: "missing",
          validity_input_digest: nil,
          creation_event: nil,
          terminal_event: nil
        )
      end

      def invalid_obligation(natural_key, obligation_id, source, target, policy, creation_event)
        ObligationCheckV1.new(
          obligation_id:,
          source_candidate_id: source.subject.candidate_id,
          target_candidate_id: target.subject.candidate_id,
          enforcement: policy.enforcement,
          required_evidence: policy.required_evidence,
          identity_digest: natural_key.digest,
          status: "invalidated",
          validity_input_digest: nil,
          creation_event:,
          terminal_event: nil
        )
      end

      def valid_creation?(creation, obligation_id, source, target, policy, validity_digest)
        creation.is_a?(Events::VerificationObligationCreatedV1) &&
          creation.obligation_id == obligation_id &&
          creation.source_candidate == source.subject &&
          creation.target_candidate == target.subject &&
          creation.policy == policy &&
          creation.required_evidence == policy.required_evidence &&
          creation.enforcement == policy.enforcement &&
          creation.validity_input_digest == validity_digest &&
          creation.rule_version == RULE_VERSION
      end

      def obligation_status(grouped)
        return [ "invalidated", grouped["VerificationObligationInvalidated"] ] if grouped["VerificationObligationInvalidated"]
        return [ "waived", grouped["VerificationObligationWaived"] ] if grouped["VerificationObligationWaived"]
        return [ "satisfied", grouped["VerificationObligationSatisfied"] ] if grouped["VerificationObligationSatisfied"]
        return [ "failed", grouped["VerificationObligationFailed"] ] if grouped["VerificationObligationFailed"]

        [ "open", nil ]
      end

      def append_obligation_reason(reasons, check)
        code = {
          "missing" => "required_obligation_missing",
          "open" => "required_obligation_open",
          "failed" => "required_obligation_failed",
          "invalidated" => "required_obligation_invalidated"
        }[check.status]
        return unless code

        reasons << reason(
          code:,
          message: "Required Candidate compatibility obligation is #{check.status}",
          source_candidate_id: check.source_candidate_id,
          target_candidate_id: check.target_candidate_id,
          obligation_id: check.obligation_id,
          obligation_status: check.status
        )
      end

      def evaluation(command, snapshot:, current_policy:, candidates:, work_item_progress:, obligations:, reasons:)
        EvaluationV1.new(
          merge_snapshot_id: command.merge_snapshot_id,
          snapshot:,
          target_base_observation: command.target_base_observation,
          current_policy:,
          candidates:,
          work_item_progress:,
          obligations:,
          reasons: reasons.freeze
        )
      end

      def reason(code:, message:, **attributes)
        defaults = {
          candidate_id: nil,
          work_item_id: nil,
          dependency_id: nil,
          source_candidate_id: nil,
          target_candidate_id: nil,
          obligation_id: nil,
          obligation_status: nil,
          expected_reference: nil,
          observed_reference: nil,
          expected_digest: nil,
          observed_digest: nil,
          expected_oid: nil,
          observed_oid: nil
        }
        ReasonV1.new(defaults.merge(attributes).merge(code:, message:))
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
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
    end
  end
end
