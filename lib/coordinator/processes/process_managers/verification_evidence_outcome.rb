# frozen_string_literal: true

module Coordinator::Processes
  module ProcessManagers
    class VerificationEvidenceOutcome
      RULE_VERSION = "verification-evidence-outcome/v1"
      HANDLED_CODES = %i[
        verification_obligation_terminal
        verification_obligation_not_satisfied
        verification_obligation_not_failed
      ].freeze

      def initialize(
        event_store:,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        state_loader: Coordinator::Write::VerificationObligations::OutcomeStateLoader.new(event_store:),
        selector: Coordinator::Write::VerificationObligations::OutcomeSelector.new,
        process_step_planner: Coordinator::Processes::ProcessStepPlanner.new(event_store:),
        satisfy: Coordinator::Write::Operations::ExecuteSatisfyVerificationObligation.new(event_store:),
        fail_obligation: Coordinator::Write::Operations::ExecuteFailVerificationObligation.new(event_store:)
      )
        @schema_registry = schema_registry
        @state_loader = state_loader
        @selector = selector
        @process_step_planner = process_step_planner
        @satisfy = satisfy
        @fail_obligation = fail_obligation
      end

      def call(event)
        evidence = load_evidence(event)
        state = @state_loader.call(evidence.obligation_id, through_revision: event.stream_revision)
        decision = @selector.call(state:, triggering_evidence_id: evidence.evidence_id)
        return unless decision.terminal?

        process_step = @process_step_planner.call(
          source_event: event,
          process_name: "verification-evidence-outcome",
          step_name: decision.kind,
          subject_kind: "verification-obligation",
          subject_id: evidence.obligation_id,
          rule_version: RULE_VERSION,
          allocate_target_entity: false
        )
        command = build_command(process_step.target_command_id, evidence, decision)
        operation = decision.kind == "satisfied" ? @satisfy : @fail_obligation
        result = operation.call(command, caused_by: process_step.event)
        return result.value! if result.success?
        return if HANDLED_CODES.include?(result.failure.code)

        failure = result.failure
        raise VerificationEvidenceOutcomeProcessRejected,
              "Verification outcome dispatch failed: #{failure.code} - #{failure.message}"
      end

      private

      def load_evidence(event)
        unless event.type == "VerificationEvidenceSubmitted" &&
               event.metadata.fetch("schema_version") == 2
          raise VerificationEvidenceOutcomeProcessRejected, "Unsupported verification evidence source"
        end

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def build_command(command_id, evidence, decision)
        actor = { kind: "system", id: "verification-evidence-outcome" }
        if decision.kind == "satisfied"
          Coordinator::Write::Commands::SatisfyVerificationObligation.new(
            command_id:,
            actor:,
            obligation_id: evidence.obligation_id,
            triggering_evidence_id: evidence.evidence_id,
            selected_evidence_ids: decision.selected_evidence.map { _1.evidence.evidence_id }
          )
        else
          Coordinator::Write::Commands::FailVerificationObligation.new(
            command_id:,
            actor:,
            obligation_id: evidence.obligation_id,
            triggering_evidence_id: evidence.evidence_id,
            reason: "submitted_evidence_failed"
          )
        end
      end
    end
  end
end
