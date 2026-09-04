# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteSubmitCompatibilityAssessment < Dry::Operation
      TOOL_NAME = "compatibility_assessment_submit"

      def initialize(
        event_store:,
        preparer: PrepareSubmitCompatibilityAssessment.new,
        decider: Domain::VerificationEvidence::Submit.new,
        input_digest: CommandInputDigest.new,
        assessment_input_digest: CompatibilityAssessments::AssessmentInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        definition_loader: VerificationObligations::DefinitionLoader.new(event_store:),
        policy_loader: CandidateObligations::ImpactPolicyLoader.new(event_store:),
        history_contract: Contracts::VerificationEvidenceHistory.new,
        event_plan_contract: Contracts::VerificationEvidenceEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
        @decider = decider
        @input_digest = input_digest
        @assessment_input_digest = assessment_input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @completion_builder = completion_builder
        @definition_loader = definition_loader
        @policy_loader = policy_loader
        @history_contract = history_contract
        @event_plan_contract = event_plan_contract
      end

      def call(input)
        command = step @preparer.call(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        steps do
          preparation = prepare_logical_values(command)

          step @event_store.multiple { execute_attempt(command:, preparation:, caused_by:) }
        end
      end

      private

      def prepare_logical_values(command)
        CompatibilityAssessmentPreparationV1.new(
          evidence_id: @id_generator.uuid_v7,
          submitted_at: @clock.now,
          input_digest: @input_digest.compatibility_assessment_submit(command),
          assessment_input_digest: @assessment_input_digest.call(command),
          evidence_event_id: @id_generator.uuid_v7,
          correlation_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        state = load_state(command.obligation_id, preparation.submitted_at)
        decision = @decider.call(
          state:,
          command:,
          evidence_id: preparation.evidence_id,
          assessment_input_digest: preparation.assessment_input_digest,
          submitted_at: preparation.submitted_at
        )
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(plan, state:, command:, preparation:)
        persisted_events = persist_domain_plan(
          plan,
          state:,
          command:,
          preparation:,
          caused_by:
        )
        completion = @completion_builder.compatibility_assessment_submit(
          command:,
          evidence: plan.events.first,
          input_digest: preparation.input_digest,
          assessment_input_digest: preparation.assessment_input_digest,
          persisted_events:,
          completed_at: preparation.submitted_at
        )

        Success(completion)
      end

      def load_state(obligation_id, observed_at)
        stream = @stream_factory.verification_obligation(obligation_id)
        definition = @definition_loader.call(obligation_id)
        grouped = @event_store.read_grouped(
          stream,
          EventQueries::VERIFICATION_OBLIGATION_FOR_EVIDENCE
        ).to_h { [ _1.type, _1 ] }
        evidence_events = @event_store.read(stream, EventQueries::VERIFICATION_EVIDENCE_HISTORY)
        claim = grouped["VerificationObligationClaimed"]
        satisfied = grouped["VerificationObligationSatisfied"]
        failed = grouped["VerificationObligationFailed"]
        waived = grouped["VerificationObligationWaived"]
        invalidated = grouped["VerificationObligationInvalidated"]
        obligation = definition&.definition
        state = Domain::VerificationEvidence::State.new(
          obligation:,
          obligation_event: definition&.reference,
          latest_claim: claim ? load_event(claim) : nil,
          latest_claim_event: claim ? event_reference(claim) : nil,
          evidence: evidence_events.map do |event|
            CompatibilityAssessments::EvidenceObservationV2.new(
              evidence: load_event(event),
              event: event_reference(event),
              assessment_input_digest: event.metadata.fetch("assessment_input_digest"),
              obligation_validity_input_digest: event.metadata.fetch("obligation_validity_input_digest"),
              policy: CandidateObligations::ImpactPolicyEvidenceV1.new(
                deep_symbolize(event.metadata.fetch("policy"))
              )
            )
          end,
          satisfied: satisfied ? load_event(satisfied) : nil,
          failed: failed ? load_event(failed) : nil,
          waived: waived ? load_event(waived) : nil,
          invalidated: invalidated ? load_event(invalidated) : nil,
          policy_current: current_policy?(
            obligation,
            observed_at,
            terminal: satisfied || failed || waived || invalidated
          )
        )
        verify_history!(state, obligation_id:)
        state
      end

      def current_policy?(obligation, observed_at, terminal:)
        return false unless obligation
        return false if terminal

        observation = @policy_loader.call(
          policy_partition_event: obligation.policy.partition_event,
          policy_head: obligation.policy.head,
          change_set_id: obligation.change_set_id,
          observed_at:
        )
        observation.status == "gating" && observation.evidence == obligation.policy
      end

      def verify_history!(state, obligation_id:)
        validation = @history_contract.call(state:, obligation_id:)
        return if validation.success?

        raise InvalidVerificationEvidenceHistory, validation.errors.to_h.inspect
      end

      def verify_event_plan!(plan, state:, command:, preparation:)
        validation = @event_plan_contract.call(
          plan:,
          state:,
          command:,
          evidence_id: preparation.evidence_id,
          assessment_input_digest: preparation.assessment_input_digest,
          submitted_at: preparation.submitted_at
        )
        return if validation.success?

        raise InvalidVerificationEvidenceEventPlan, validation.errors.to_h.inspect
      end

      def persist_domain_plan(plan, state:, command:, preparation:, caused_by:)
        physical = plan.events.map do |event|
          @event_factory.build!(
            event:,
            event_id: preparation.evidence_event_id,
            metadata: command_metadata(command, state.obligation, preparation),
            markers: event_markers(state, command, event),
            caused_by:,
            correlation_id: root_correlation_id(preparation, caused_by)
          )
        end
        @event_store.append(plan.writes.first.stream, physical)
      end

      def root_correlation_id(preparation, caused_by)
        preparation.correlation_id unless caused_by
      end

      def event_markers(state, command, event)
        common = scope_markers(state.obligation) + [ "command:#{command.command_id}" ]
        case event
        when Events::VerificationEvidenceSubmittedV2
          common + [
            "verification-evidence:#{event.evidence_id}",
            "verification-evidence-kind:#{event.evidence_kind}",
            "verification-evidence-conclusion:#{event.assessment.conclusion}",
            "claim:#{event.claim.claim_id}",
            "claimant:#{event.claim.claimant_id}"
          ]
        end
      end

      def scope_markers(obligation)
        source = obligation.source_candidate
        target = obligation.target_candidate
        [
          "verification-obligation:#{obligation.obligation_id}",
          "verification-obligation-kind:#{obligation.kind}",
          "change-set:#{obligation.change_set_id}",
          "source-candidate:#{source.candidate_id}",
          "target-candidate:#{target.candidate_id}",
          "candidate:#{source.candidate_id}",
          "candidate:#{target.candidate_id}",
          "work-item:#{source.work_item_id}",
          "work-item:#{target.work_item_id}",
          "repository:#{source.repository_id}",
          "repository:#{target.repository_id}",
          "enforcement:#{obligation.enforcement}",
          "decision:#{obligation.policy.head.decision_id}"
        ]
      end

      def command_metadata(command, obligation, preparation)
        Metadata::VerificationEvidenceV2.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "compatibility-assessment/v2",
          assessment_input_digest: preparation.assessment_input_digest,
          obligation_validity_input_digest: obligation.validity_input_digest,
          policy: obligation.policy
        )
      end

      def deep_symbolize(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, deep_symbolize(nested) ] }
        when Array then value.map { deep_symbolize(_1) }
        else value
        end
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
