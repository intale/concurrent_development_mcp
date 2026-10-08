# frozen_string_literal: true

module Coordinator::Write
  class CommandResultBuilder
    def initialize(
      persisted_events_contract: Contracts::PersistedEvents.new
    )
      @persisted_events_contract = persisted_events_contract
    end

    def create_change_set(command:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "change_set_create",
        summary: "ChangeSet created.",
        data: CommandReceiptData::ChangeSet.new(change_set_id: command.change_set_id),
        next_actions: [],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def work_item_create(command:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "work_item_create",
        summary: "WorkItem created.",
        data: CommandReceiptData::WorkItem.new(
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id
        ),
        next_actions: [],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def work_item_dependency_declare(command:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "work_item_dependency_declare",
        summary: "WorkItem dependency declared.",
        data: CommandReceiptData::Dependency.new(
          change_set_id: command.change_set_id,
          dependency_id: command.dependency_id
        ),
        next_actions: [],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def change_set_activate(command:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "change_set_activate",
        summary: "ChangeSet activated.",
        data: CommandReceiptData::ChangeSet.new(change_set_id: command.change_set_id),
        next_actions: [
          NextAction.new(
            tool: "coord_context",
            arguments: NextAction::ChangeSetArguments.new(change_set_id: command.change_set_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def work_item_acquire(command:, input_digest:, persisted_events:, completed_at:)
      attempt_arguments = NextAction::AttemptArguments.new(
        change_set_id: command.change_set_id,
        work_item_id: command.work_item_id,
        attempt_id: command.attempt_id
      )

      build_completion(
        command:,
        tool_name: "work_item_acquire",
        summary: "WorkItem acquired and Attempt started.",
        data: CommandReceiptData::Attempt.new(attempt_arguments.to_h),
        next_actions: [],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def work_item_complete(command:, candidate_event:, input_digest:, persisted_events:, completed_at:)
      selected_event = persisted_events.find { _1.type == "WorkItemCandidateSelected" }
      attempt_event = persisted_events.find { _1.type == "AttemptCompleted" }
      completed_event = persisted_events.find { _1.type == "WorkItemCompleted" }
      build_completion(
        command:,
        tool_name: "work_item_complete",
        summary: "Final Candidate selected; WorkItem and Attempt completed.",
        data: CommandReceiptData::WorkItemCompletion.new(
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          candidate_id: command.candidate_id,
          candidate_event:,
          selected_event: event_reference(selected_event),
          attempt_completed_event: event_reference(attempt_event),
          work_item_completed_event: event_reference(completed_event),
          produced_outputs: command.produced_outputs,
          completed_at:
        ),
        next_actions: [
          NextAction.new(
            tool: "coord_context",
            arguments: NextAction::ChangeSetArguments.new(change_set_id: command.change_set_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def write_set_reserve(command:, reservation:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "work_intention_set_declare",
        summary: "Resource work intentions declared.",
        data: CommandReceiptData::WorkIntentionSetDeclaration.new(
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          repository_id: command.repository_id,
          intention_set_id: reservation.intention_set_id,
          policy_version: reservation.policy_version,
          declared_at: reservation.declared_at,
          expires_at: reservation.expires_at,
          intentions: reservation.intentions
        ),
        next_actions: [
          NextAction.new(
            tool: "coord_context",
            arguments: NextAction::ChangeSetArguments.new(change_set_id: command.change_set_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def write_set_expand(command:, expansion:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "work_intention_set_expand",
        summary: "Work-intention set expanded.",
        data: CommandReceiptData::WorkIntentionSetExpansion.new(
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          repository_id: command.repository_id,
          intention_set_id: expansion.intention_set_id,
          policy_version: expansion.policy_version,
          expanded_at: expansion.expanded_at,
          expires_at: expansion.expires_at,
          added_intentions: expansion.added_intentions,
          intention_count: expansion.intention_count
        ),
        next_actions: [
          NextAction.new(
            tool: "coord_context",
            arguments: NextAction::ChangeSetArguments.new(change_set_id: command.change_set_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def lease_renew(command:, renewal:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "work_intention_set_renew",
        summary: "Work-intention set renewed.",
        data: CommandReceiptData::WorkIntentionSetRenewal.new(
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          repository_id: renewal.repository_id,
          intention_set_id: renewal.intention_set_id,
          policy_version: renewal.policy_version,
          intentions: renewal.intentions,
          intention_count: renewal.intention_count,
          renewed_at: renewal.renewed_at,
          previous_expires_at: renewal.previous_expires_at,
          expires_at: renewal.expires_at
        ),
        next_actions: [
          NextAction.new(
            tool: "coord_context",
            arguments: NextAction::ChangeSetArguments.new(change_set_id: command.change_set_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def lease_release(command:, release:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "work_intention_set_withdraw",
        summary: "Work-intention set withdrawn.",
        data: CommandReceiptData::WorkIntentionSetWithdrawal.new(
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          repository_id: release.repository_id,
          intention_set_id: release.intention_set_id,
          policy_version: release.policy_version,
          intentions: release.intentions,
          intention_count: release.intention_count,
          previous_expires_at: release.previous_expires_at,
          withdrawn_at: release.withdrawn_at
        ),
        next_actions: [
          NextAction.new(
            tool: "coord_context",
            arguments: NextAction::ChangeSetArguments.new(change_set_id: command.change_set_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def lease_expire_policy(command:, expiration:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "lease_expire_policy",
        summary: "Resource lease explicitly expired.",
        data: CommandReceiptData::ResourceLeaseExpiry.new(
          resource_id: expiration.resource_id,
          lease_id: expiration.lease_id,
          lease_set_id: expiration.lease_set_id,
          fencing_token: expiration.fencing_token,
          expires_at: expiration.expires_at,
          expired_at: expiration.expired_at
        ),
        next_actions: [],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def guidance_record(command:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "guidance_record",
        summary: "Guidance evidence recorded without activating policy.",
        data: CommandReceiptData::Guidance.new(
          message_id: command.message_id,
          conversation_id: command.conversation_id,
          source: command.source,
          policy_status: "evidence_only",
          recorded_at: completed_at
        ),
        next_actions: [
          NextAction.new(
            tool: "guidance_get",
            arguments: NextAction::GuidanceArguments.new(message_id: command.message_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def decision_interpretation_propose(command:, assessment:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "decision_interpretation_propose",
        summary: "Atomic decision interpretation proposed without activating policy.",
        data: CommandReceiptData::InterpretationProposal.new(
          interpretation_id: command.interpretation_id,
          source_message_id: command.source_message_id,
          assessment:,
          proposed_at: completed_at
        ),
        next_actions: [
          NextAction.new(
            tool: "decision_interpretation_list",
            arguments: NextAction::InterpretationListArguments.new(
              message_id: command.source_message_id
            )
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def decision_interpretation_adjudicate(command:, slot:, input_digest:, persisted_events:, completed_at:)
      outcome = {
        "accept" => "accepted_for_activation",
        "reject" => "rejected",
        "request_clarification" => "clarification_required"
      }.fetch(command.action)
      build_completion(
        command:,
        tool_name: "decision_interpretation_adjudicate",
        summary: "Interpretation adjudication recorded without activating policy.",
        data: CommandReceiptData::InterpretationAdjudication.new(
          interpretation_id: command.interpretation_id,
          source_message_id: command.source_message_id,
          action: command.action,
          outcome:,
          policy_status: "proposal_only",
          slot: command.action == "accept" ? slot : nil,
          adjudicated_at: completed_at
        ),
        next_actions: [
          NextAction.new(
            tool: "decision_interpretation_list",
            arguments: NextAction::InterpretationListArguments.new(
              message_id: command.source_message_id
            )
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def decision_activate(
      command:,
      activation:,
      definition_digest:,
      slot:,
      partitions:,
      input_digest:,
      persisted_events:,
      completed_at:
    )
      build_completion(
        command:,
        tool_name: "decision_activate",
        summary: "Accepted interpretation activated as authoritative policy.",
        data: CommandReceiptData::DecisionActivation.new(
          decision_id: command.decision_id,
          interpretation_id: command.interpretation_id,
          outcome: "activated",
          policy_status: "active",
          definition_digest:,
          slot:,
          partitions:,
          activated_at: completed_at
        ),
        next_actions: [
          NextAction.new(
            tool: "decision_get",
            arguments: NextAction::DecisionArguments.new(decision_id: command.decision_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def decision_correct(
      command:,
      correction:,
      previous_definition_digest:,
      definition_digest:,
      slot:,
      correction_event:,
      partitions:,
      input_digest:,
      persisted_events:,
      completed_at:
    )
      build_completion(
        command:,
        tool_name: "decision_correct",
        summary: "Active Decision definition corrected from accepted interpretation evidence.",
        data: CommandReceiptData::DecisionCorrection.new(
          decision_id: command.decision_id,
          interpretation_id: command.interpretation_id,
          outcome: "corrected",
          policy_status: "active",
          previous_definition_digest:,
          definition_digest:,
          correction_event:,
          slot:,
          partitions:,
          corrected_at: completed_at
        ),
        next_actions: [
          NextAction.new(
            tool: "decision_get",
            arguments: NextAction::DecisionArguments.new(decision_id: command.decision_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def agent_choice_record(
      command:,
      recorded:,
      acceptance:,
      context_digest:,
      input_digest:,
      persisted_events:,
      completed_at:
    )
      build_completion(
        command:,
        tool_name: "agent_choice_record",
        summary: "Agent choice recorded and accepted against authoritative Decision context.",
        data: CommandReceiptData::AgentChoice.new(
          choice_id: command.choice_id,
          choice_type: command.choice_type,
          outcome: "accepted",
          assessment_basis: acceptance.assessment.basis,
          context_digest:,
          recorded_event: event_reference(persisted_events.fetch(0)),
          accepted_event: event_reference(persisted_events.fetch(1)),
          based_on_decisions: acceptance.assessment.based_on_decisions,
          warnings: acceptance.assessment.warnings,
          accepted_at: completed_at
        ),
        next_actions: [
          NextAction.new(
            tool: "agent_choice_get",
            arguments: NextAction::AgentChoiceArguments.new(choice_id: command.choice_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def candidate_submit(command:, input_digest:, persisted_events:, completed_at:)
      candidate_event = persisted_events.find { _1.type == "CandidateSubmitted" }
      build_completion(
        command:,
        tool_name: "candidate_submit",
        summary: "Candidate submitted with attributed, unverified source evidence.",
        data: CommandReceiptData::CandidateSubmission.new(
          candidate_id: command.candidate_id,
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          repository_id: command.repository_id,
          target_branch: command.target_branch,
          object_format: command.object_format,
          base_commit_oid: command.base_commit_oid,
          head_commit_oid: command.head_commit_oid,
          checkpoint_kind: command.checkpoint_kind,
          manifest_digest: command.manifest.digest,
          build_context_digest: command.build_context&.digest,
          evidence_status: "attributed_unverified",
          candidate_event: event_reference(candidate_event),
          submitted_at: candidate_event.created_at.utc.iso8601(6)
        ),
        next_actions: [
          NextAction.new(
            tool: "candidate_get",
            arguments: NextAction::CandidateArguments.new(candidate_id: command.candidate_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def skill_publish(command:, revision:, outcome:, publication_event:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "skill_publish",
        summary: outcome == "published" ?
          "Skill revision published as cohesive immutable facts." :
          "The requested Skill revision content is already published.",
        data: CommandReceiptData::SkillPublication.new(
          skill_id: command.skill_id,
          name: command.name,
          scope: command.scope,
          revision:,
          content_digest: command.content_digest,
          asset_count: command.assets.length,
          publication_event: event_reference(publication_event),
          published_at: publication_event.created_at.utc.iso8601(6)
        ),
        next_actions: [
          NextAction.new(
            tool: "skill_get",
            arguments: NextAction::SkillArguments.new(name: command.name, scope: command.scope)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def development_artifact_capture(command:, decision:, input_digest:, persisted_events:, completed_at:)
      granular = decision.respond_to?(:artifact)
      artifact = granular ? decision.artifact : decision.capture.artifact
      observation = granular ? decision.observation : decision.observation.observation
      outcome = decision.outcome == "created" ? "captured" : decision.outcome
      recorded_event = persisted_events.find { _1.type == "DevelopmentArtifactObservationRecorded" }
      build_completion(
        command:,
        tool_name: "development_artifact_capture",
        summary: case outcome
                 when "captured" then "Development Artifact content and observation captured."
                 when "observed" then "Development Artifact observation captured for existing content."
                 when "existing" then "Development Artifact observation already exists."
                 end,
        data: CommandReceiptData::DevelopmentArtifactCapture.new(
          artifact_id: artifact.artifact_id,
          observation_id: observation.observation_id,
          classification_revision: 1,
          scope: observation.scope,
          kind: observation.kind,
          content_sha256: artifact.content.content_sha256,
          byte_size: artifact.content.byte_size,
          outcome:,
          recorded_at: recorded_event&.created_at&.utc&.iso8601(6) ||
            (granular ? completed_at : decision.observation.recorded_at)
        ),
        next_actions: [
          NextAction.new(
            tool: "development_artifact_get",
            arguments: NextAction::DevelopmentArtifactArguments.new(
              artifact_id: artifact.artifact_id,
              observation_id: observation.observation_id
            )
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def development_artifact_update(command:, decision:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "development_artifact_update",
        summary: decision.outcome == "updated" ?
          "Development Artifact properties updated as granular facts." :
          "Development Artifact already has the requested properties.",
        data: CommandReceiptData::DevelopmentArtifactUpdate.new(
          artifact_id: decision.artifact_id,
          resulting_stream_revision: persisted_events.last&.stream_revision || command.expected_revision,
          changed_properties: decision.changed_properties,
          outcome: decision.outcome,
          updated_at: persisted_events.last&.created_at&.utc&.iso8601(6) || completed_at
        ),
        next_actions: [
          NextAction.new(
            tool: "development_artifact_get",
            arguments: NextAction::DevelopmentArtifactArguments.new(artifact_id: decision.artifact_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def development_artifact_classification_correct(
      command:,
      decision:,
      input_digest:,
      persisted_events:,
      completed_at:
    )
      build_completion(
        command:,
        tool_name: "development_artifact_classification_correct",
        summary: case decision.outcome
                 when "corrected" then "Development Artifact observation classification corrected."
                 when "existing" then "Development Artifact observation classification is already current."
                 end,
        data: CommandReceiptData::DevelopmentArtifactClassification.new(
          artifact_id: decision.respond_to?(:artifact_id) ? decision.artifact_id : decision.observation.observation.artifact_id,
          observation_id: command.observation_id,
          classification_revision: decision.classification_revision,
          title: decision.respond_to?(:title) ? decision.title : decision.observation.title,
          kind: decision.respond_to?(:kind) ? decision.kind : decision.observation.kind,
          labels: decision.respond_to?(:labels) ? decision.labels : decision.observation.labels,
          outcome: decision.outcome,
          corrected_at: persisted_events.last&.created_at&.utc&.iso8601(6) || completed_at
        ),
        next_actions: [
          NextAction.new(
            tool: "development_artifact_get",
            arguments: NextAction::DevelopmentArtifactArguments.new(
              artifact_id: decision.respond_to?(:artifact_id) ? decision.artifact_id : decision.observation.observation.artifact_id,
              observation_id: command.observation_id
            )
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def development_artifact_relation_declare(command:, decision:, input_digest:, persisted_events:, completed_at:)
      granular = decision.respond_to?(:relation_id)
      artifact_relation = granular ? command.artifact_relation : decision.declaration.artifact_relation
      supersession = granular ? nil : decision.supersession
      declaration_event = persisted_events.find { _1.type == "DevelopmentArtifactRelationDeclared" }
      supersession_event = persisted_events.find { _1.type == "DevelopmentArtifactRelationSuperseded" }
      build_completion(
        command:,
        tool_name: "development_artifact_relation_declare",
        summary: case decision.outcome
                 when "declared" then "Development Artifact relation declared."
                 when "superseded" then "Development Artifact relation superseded."
                 when "existing" then "Development Artifact relation already exists."
                 end,
        data: CommandReceiptData::DevelopmentArtifactRelation.new(
          relation_id: artifact_relation.relation_id,
          source_artifact_id: artifact_relation.source_artifact_id,
          relation: artifact_relation.relation,
          target: artifact_relation.target,
          superseded_relation_id: granular ? command.supersedes_relation_id : supersession&.superseded_relation_id,
          outcome: decision.outcome,
          declared_at: granular ?
            (declaration_event&.created_at&.utc&.iso8601(6) || completed_at) :
            decision.declaration.declared_at,
          superseded_at: granular ?
            supersession_event&.created_at&.utc&.iso8601(6) :
            supersession&.superseded_at
        ),
        next_actions: [
          NextAction.new(
            tool: "development_artifact_get",
            arguments: NextAction::DevelopmentArtifactArguments.new(
              artifact_id: artifact_relation.source_artifact_id
            )
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def operation_batch_create(command:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "#{command.target_tool}_batch",
        summary: "Operation Batch accepted for asynchronous processing.",
        data: CommandReceiptData::OperationBatchAcceptance.new(
          batch_id: command.batch_id,
          target_tool: command.target_tool,
          total: command.items.length,
          status: "accepted"
        ),
        next_actions: [ operation_batch_next_action(command.batch_id) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def operation_batch_cancel(command:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "operation_batch_cancel",
        summary: "Operation Batch cancellation requested; completed items remain committed.",
        data: CommandReceiptData::OperationBatchCancellation.new(
          batch_id: command.batch_id,
          status: "cancellation_requested"
        ),
        next_actions: [ operation_batch_next_action(command.batch_id) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def operation_batch_transition(command:, event:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: operation_batch_transition_tool(event),
        summary: operation_batch_transition_summary(event),
        data: CommandReceiptData::OperationBatchTransition.new(
          batch_id: command.batch_id,
          transition: operation_batch_transition_name(event),
          index: event.respond_to?(:index) ? event.index : nil
        ),
        next_actions: [],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def candidate_impact_surface_submit(
      command:,
      surface_id:,
      input_digest:,
      persisted_events:,
      completed_at:
    )
      surface_event = persisted_events.find { _1.type == "CandidateImpactSurfaceDerived" }
      assignment_event = persisted_events.find { _1.type == "CandidateImpactSurfaceAssigned" }
      build_completion(
        command:,
        tool_name: "candidate_impact_surface_submit",
        summary: "Candidate semantic-impact surface recorded as attributed, unverified evidence.",
        data: CommandReceiptData::CandidateImpactSurface.new(
          candidate_id: command.candidate_id,
          surface_id:,
          surface_digest: command.surface.digest,
          evidence_revision: surface_event.data.fetch("evidence_revision"),
          evidence_status: "attributed_unverified",
          surface_event: event_reference(surface_event),
          registration_event: event_reference(assignment_event),
          derived_at: surface_event.created_at.utc.iso8601(6)
        ),
        next_actions: [],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def verification_obligation_claim(command:, claim:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "verification_obligation_claim",
        summary: "Verification obligation claimed for temporary exclusive coordination.",
        data: CommandReceiptData::VerificationObligationClaim.new(
          obligation_id: command.obligation_id,
          claim_id: claim.claim_id,
          claimant_id: claim.claimant_id,
          fencing_token: claim.fencing_token,
          claimed_at: persisted_events.fetch(0).created_at.utc.iso8601(6),
          expires_at: claim.expires_at,
          claim_event: event_reference(persisted_events.fetch(0))
        ),
        next_actions: [
          NextAction.new(
            tool: "verification_obligations_list",
            arguments: NextAction::VerificationObligationArguments.new(
              obligation_id: command.obligation_id
            )
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def compatibility_assessment_submit(
      command:,
      evidence:,
      input_digest:,
      assessment_input_digest:,
      persisted_events:,
      completed_at:
    )
      status = "open"
      build_completion(
        command:,
        tool_name: "compatibility_assessment_submit",
        summary: compatibility_assessment_summary(status),
        data: CommandReceiptData::CompatibilityAssessment.new(
          obligation_id: command.obligation_id,
          evidence_id: evidence.evidence_id,
          evidence_kind: evidence.evidence_kind,
          conclusion: evidence.assessment.conclusion,
          status:,
          assessment_input_digest:,
          evidence_event: event_reference(persisted_events.fetch(0)),
          outcome_event: nil,
          submitted_at: persisted_events.fetch(0).created_at.utc.iso8601(6)
        ),
        next_actions: [
          NextAction.new(
            tool: "verification_obligations_list",
            arguments: NextAction::VerificationObligationArguments.new(
              obligation_id: command.obligation_id
            )
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def verification_obligation_waive(
      command:,
      waiver:,
      input_digest:,
      persisted_events:,
      completed_at:
    )
      build_completion(
        command:,
        tool_name: "verification_obligation_waive",
        summary: "Exact verification obligation waived by user-attributed coordination decision.",
        data: CommandReceiptData::VerificationObligationWaiver.new(
          obligation_id: command.obligation_id,
          previous_status: "open",
          status: "waived",
          reason: waiver.reason,
          waiver_event: event_reference(persisted_events.sole),
          waived_at: persisted_events.sole.created_at.utc.iso8601(6)
        ),
        next_actions: [
          NextAction.new(
            tool: "verification_obligations_list",
            arguments: NextAction::VerificationObligationArguments.new(
              obligation_id: command.obligation_id
            )
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def merge_snapshot_register(command:, snapshot_digest:, input_digest:, persisted_events:, completed_at:, registered_at:)
      build_completion(
        command:,
        tool_name: "merge_snapshot_register",
        summary: "Attributed external merge snapshot registered.",
        data: CommandReceiptData::MergeSnapshotRegistration.new(
          merge_snapshot_id: command.merge_snapshot_id,
          repository_id: command.repository_id,
          target_branch: command.target_branch,
          object_format: command.object_format,
          target_base_commit_oid: command.target_base_commit_oid,
          ordered_candidates: command.ordered_candidates,
          merge_commit_oid: command.merge_commit_oid,
          snapshot_digest:,
          evidence_status: "attributed_unverified",
          snapshot_event: event_reference(persisted_events.fetch(0)),
          registered_at:
        ),
        next_actions: [
          NextAction.new(
            tool: "merge_snapshot_get",
            arguments: NextAction::MergeSnapshotArguments.new(
              merge_snapshot_id: command.merge_snapshot_id
            )
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def merge_verification_submit(
      command:,
      submission:,
      verification_input_digest:,
      input_digest:,
      persisted_events:,
      completed_at:
    )
      status = submission.assessment.conclusion == "passed" ?
        "unverified" : submission.assessment.conclusion
      build_completion(
        command:,
        tool_name: "merge_verification_submit",
        summary: merge_verification_summary(status),
        data: CommandReceiptData::MergeSnapshotVerification.new(
          merge_snapshot_id: command.merge_snapshot_id,
          verification_id: submission.verification_id,
          evidence_kind: submission.assessment.evidence_kind,
          conclusion: submission.assessment.conclusion,
          status:,
          verification_input_digest:,
          submitted_event: event_reference(persisted_events.fetch(0)),
          verified_event: nil,
          submitted_at: persisted_events.fetch(0).created_at.utc.iso8601(6)
        ),
        next_actions: [
          NextAction.new(
            tool: "merge_snapshot_get",
            arguments: NextAction::MergeSnapshotArguments.new(
              merge_snapshot_id: command.merge_snapshot_id
            )
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def merge_authorization_request(
      command:,
      decision:,
      decision_digest:,
      input_digest:,
      persisted_events:,
      completed_at:,
      decided_at:
    )
      outcome = decision.is_a?(Events::MergeAuthorizationGrantedV2) ? "granted" : "denied"
      build_completion(
        command:,
        tool_name: "merge_authorization_request",
        summary: merge_authorization_summary(outcome),
        data: CommandReceiptData::MergeAuthorization.new(
          authorization_id: decision.authorization_id,
          merge_snapshot_id: command.merge_snapshot_id,
          outcome:,
          decision_digest:,
          decision_event: event_reference(persisted_events.sole),
          reasons: decision.evaluation.reasons,
          obligations: decision.evaluation.obligations,
          work_item_progress: decision.evaluation.work_item_progress,
          decided_at:
        ),
        next_actions: [
          NextAction.new(
            tool: "merge_snapshot_get",
            arguments: NextAction::MergeSnapshotArguments.new(
              merge_snapshot_id: command.merge_snapshot_id
            )
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def merge_observation_record(
      command:,
      observation:,
      observation_digest:,
      input_digest:,
      persisted_events:,
      completed_at:,
      recorded_at:
    )
      build_completion(
        command:,
        tool_name: "merge_observation_record",
        summary: "Attributed external merge transition recorded; the coordinator did not perform or verify it.",
        data: CommandReceiptData::MergeObservation.new(
          merge_snapshot_id: command.merge_snapshot_id,
          authorization_event: command.authorization_event,
          authorization_decision_digest: command.authorization_decision_digest,
          repository_id: command.repository_id,
          target_branch: command.target_branch,
          object_format: command.object_format,
          target_before_commit_oid: command.target_before_commit_oid,
          target_after_commit_oid: command.target_after_commit_oid,
          observation_digest:,
          evidence_status: "attributed_unverified",
          observation_event: event_reference(persisted_events.fetch(0)),
          observed_at: command.observed_at,
          recorded_at:
        ),
        next_actions: [
          NextAction.new(
            tool: "merge_snapshot_get",
            arguments: NextAction::MergeSnapshotArguments.new(
              merge_snapshot_id: command.merge_snapshot_id
            )
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def release_set_prepare(
      command:,
      change_set_id:,
      ordered_members:,
      release_digest:,
      prepared_event:,
      input_digest:,
      persisted_events:,
      completed_at:
    )
      build_completion(
        command:,
        tool_name: "release_set_prepare",
        summary: "Immutable ordered ReleaseSet prepared from exact current authorization evidence.",
        data: CommandReceiptData::ReleaseSetPreparation.new(
          release_set_id: command.release_set_id,
          change_set_id:,
          ordered_members:,
          release_digest:,
          policy_version: command.policy_version,
          prepared_event: event_reference(prepared_event),
          prepared_at: prepared_event.created_at.utc.iso8601(6)
        ),
        next_actions: [
          NextAction.new(
            tool: "release_set_get",
            arguments: NextAction::ReleaseSetArguments.new(release_set_id: command.release_set_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def release_repository_integration_record(
      command:,
      integration:,
      integration_digest:,
      integration_event:,
      input_digest:,
      persisted_events:,
      completed_at:
    )
      build_completion(
        command:,
        tool_name: "release_repository_integration_record",
        summary: repository_integration_summary(integration.outcome),
        data: CommandReceiptData::RepositoryIntegration.new(
          release_set_id: integration.release_set_id,
          change_set_id: integration.change_set_id,
          repository_id: integration.repository_id,
          member_position: integration.member_position,
          attempt_id: integration.attempt_id,
          attempt_number: integration.attempt_number,
          outcome: integration.outcome,
          integration_digest:,
          evidence_status: "attributed_unverified",
          integration_event: event_reference(integration_event),
          recorded_at: integration_event.created_at.utc.iso8601(6)
        ),
        next_actions: [ release_set_next_action(command.release_set_id) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def release_verification_record(
      command:,
      verification:,
      integration_events:,
      verification_digest:,
      verification_event:,
      input_digest:,
      persisted_events:,
      completed_at:
    )
      build_completion(
        command:,
        tool_name: "release_verification_record",
        summary: release_verification_summary(verification.evidence.outcome),
        data: CommandReceiptData::ReleaseSetVerification.new(
          release_set_id: verification.release_set_id,
          change_set_id: verification.change_set_id,
          attempt_number: verification.attempt_number,
          outcome: verification.evidence.outcome,
          integration_events:,
          verification_digest:,
          evidence_status: "attributed_unverified",
          verification_event: event_reference(verification_event),
          recorded_at: verification_event.created_at.utc.iso8601(6)
        ),
        next_actions: [ release_set_next_action(command.release_set_id) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def release_activation_record(
      command:,
      activation:,
      activation_digest:,
      activation_event:,
      input_digest:,
      persisted_events:,
      completed_at:
    )
      build_completion(
        command:,
        tool_name: "release_activation_record",
        summary: "Attributed external ReleaseSet activation recorded; lifecycle completion is asynchronous.",
        data: CommandReceiptData::ReleaseSetActivation.new(
          release_set_id: activation.release_set_id,
          change_set_id: activation.change_set_id,
          verification_event: command.verification_event,
          verification_digest: command.verification_digest,
          activation_digest:,
          evidence_status: "attributed_unverified",
          activation_event: event_reference(activation_event),
          recorded_at: activation_event.created_at.utc.iso8601(6)
        ),
        next_actions: [ release_set_next_action(command.release_set_id) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def release_compensation_request(
      command:,
      request:,
      successful_integrations:,
      compensation_request_event:,
      input_digest:,
      persisted_events:,
      completed_at:
    )
      build_completion(
        command:,
        tool_name: "release_compensation_request_policy",
        summary: "ReleaseSet compensation requested for the exact successful integrations.",
        data: CommandReceiptData::ReleaseSetCompensationRequest.new(
          release_set_id: request.release_set_id,
          change_set_id: request.change_set_id,
          trigger_event: command.trigger_event,
          trigger_kind: request.trigger_kind,
          successful_integrations:,
          compensation_request_event: event_reference(compensation_request_event),
          requested_at: compensation_request_event.created_at.utc.iso8601(6)
        ),
        next_actions: [ release_set_next_action(command.release_set_id) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def release_activated_complete(
      command:,
      change_set_id:,
      outcome:,
      source_event:,
      completion_digest:,
      completion_event:,
      input_digest:,
      persisted_events:,
      completed_at:
    )
      release_set_completion(
        command:,
        change_set_id:,
        outcome:,
        source_event:,
        completion_digest:,
        completion_event:,
        tool_name: "release_activated_complete_policy",
        summary: "Activated ReleaseSet lifecycle completed.",
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def release_compensation_complete(
      command:,
      change_set_id:,
      outcome:,
      source_event:,
      completion_digest:,
      completion_event:,
      input_digest:,
      persisted_events:,
      completed_at:
    )
      release_set_completion(
        command:,
        change_set_id:,
        outcome:,
        source_event:,
        completion_digest:,
        completion_event:,
        tool_name: "release_compensation_complete",
        summary: "Attributed external compensation evidence completed the ReleaseSet lifecycle.",
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def dependency_satisfaction_policy(command:, satisfaction:, input_digest:, persisted_events:, completed_at:)
      source_event = satisfaction.is_a?(Events::WorkItemDependencySatisfiedV2) ?
        satisfaction.source : satisfaction.source_event
      satisfied_at = satisfaction.is_a?(Events::WorkItemDependencySatisfiedV2) ?
        completed_at : satisfaction.satisfied_at
      build_completion(
        command:,
        tool_name: "dependency_satisfaction_policy",
        summary: "WorkItem dependency satisfied from exact coordination evidence.",
        data: CommandReceiptData::DependencySatisfaction.new(
          change_set_id: satisfaction.change_set_id,
          dependency_id: satisfaction.dependency_id,
          consumer_work_item_id: satisfaction.consumer_work_item_id,
          source_event:,
          satisfaction_event: event_reference(persisted_events.fetch(0)),
          readiness_event: persisted_events[1] && event_reference(persisted_events.fetch(1)),
          satisfied_at:
        ),
        next_actions: [],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def change_set_completion_policy(
      command:,
      work_items:,
      release_set_completion_event:,
      input_digest:,
      persisted_events:,
      completed_at:
    )
      completion_event = persisted_events.find { _1.type == "ChangeSetCompleted" }
      build_completion(
        command:,
        tool_name: "change_set_completion_policy",
        summary: "ChangeSet completed from exact WorkItem and release evidence.",
        data: CommandReceiptData::ChangeSetCompletion.new(
          change_set_id: command.change_set_id,
          work_item_completions: work_items,
          release_set_completion_event:,
          completion_event: event_reference(completion_event),
          completed_at:
        ),
        next_actions: [],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    private

    def operation_batch_next_action(batch_id)
      NextAction.new(
        tool: "operation_batch_get",
        arguments: NextAction::OperationBatchArguments.new(batch_id:)
      )
    end

    def operation_batch_transition_name(event)
      case event
      when Events::OperationBatchItemSucceededV2 then "item_succeeded"
      when Events::OperationBatchItemRejectedV2 then "item_rejected"
      when Events::OperationBatchContinuationRequestedV2 then "continuation_requested"
      when Events::OperationBatchCompletedV2 then "completed"
      when Events::OperationBatchCancelledV2 then "cancelled"
      end
    end

    def operation_batch_transition_tool(event)
      {
        "item_succeeded" => "operation_batch_item_outcome_policy",
        "item_rejected" => "operation_batch_item_outcome_policy",
        "continuation_requested" => "operation_batch_continuation_policy",
        "completed" => "operation_batch_completion_policy",
        "cancelled" => "operation_batch_cancellation_completion_policy"
      }.fetch(operation_batch_transition_name(event))
    end

    def operation_batch_transition_summary(event)
      {
        "item_succeeded" => "Operation Batch item succeeded.",
        "item_rejected" => "Operation Batch item was rejected by its target command.",
        "continuation_requested" => "Operation Batch continuation requested.",
        "completed" => "Operation Batch completed.",
        "cancelled" => "Operation Batch cancelled at an item boundary."
      }.fetch(operation_batch_transition_name(event))
    end

    def release_set_completion(
      command:,
      change_set_id:,
      outcome:,
      source_event:,
      completion_digest:,
      completion_event:,
      tool_name:,
      summary:,
      input_digest:,
      persisted_events:,
      completed_at:
    )
      build_completion(
        command:,
        tool_name:,
        summary:,
        data: CommandReceiptData::ReleaseSetCompletion.new(
          release_set_id: command.release_set_id,
          change_set_id:,
          outcome:,
          source_event:,
          completion_digest:,
          completion_event: event_reference(completion_event),
          completed_at: completion_event.created_at.utc.iso8601(6)
        ),
        next_actions: [ release_set_next_action(command.release_set_id) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def verification_status(persisted_events)
      case persisted_events[1]&.type
      when "VerificationObligationSatisfied" then "satisfied"
      when "VerificationObligationFailed" then "failed"
      else "open"
      end
    end

    def merge_authorization_summary(outcome)
      return "Recorded evidence satisfies merge-authorization policy; the external merge has not been performed." if outcome == "granted"

      "Merge authorization was denied from the exact recorded evidence; the external merge was not performed."
    end

    def repository_integration_summary(outcome)
      return "Attributed external repository integration recorded for the immutable ReleaseSet member." if outcome == "integrated"

      "Attributed external repository integration failure recorded; the ReleaseSet may require retry or compensation."
    end

    def release_verification_summary(outcome)
      return "Attributed composite verification passed for the exact integrated ReleaseSet." if outcome == "passed"

      "Attributed composite verification failure recorded for the exact integrated ReleaseSet."
    end

    def release_set_next_action(release_set_id)
      NextAction.new(
        tool: "release_set_get",
        arguments: NextAction::ReleaseSetArguments.new(release_set_id:)
      )
    end

    def compatibility_assessment_summary(status)
      case status
      when "satisfied" then "Compatibility evidence accepted; verification obligation satisfied."
      when "failed" then "Compatibility evidence accepted; verification obligation failed."
      else "Compatibility evidence accepted; verification obligation remains open."
      end
    end

    def merge_verification_summary(status)
      return "Combined-test evidence accepted; exact merge snapshot verified." if status == "verified"

      "Combined-test evidence accepted; exact merge snapshot remains unverified."
    end

    def build_completion(command:, tool_name:, summary:, data:, next_actions:, input_digest:, persisted_events:, completed_at:)
      events = apply_persisted_events_contract(persisted_events)
      emitted_events = events.map { event_reference(_1) }

      CommandResultV1.new(
        command_id: command.command_id,
        tool_name:,
        canonical_input_digest: input_digest,
        status: "ok",
        summary:,
        receipt: command.command_id,
        data:,
        warnings: [],
        next_actions:,
        emitted_events:,
        completed_at:
      )
    end

    def apply_persisted_events_contract(events)
      result = @persisted_events_contract.call(events:)
      return result.to_h.fetch(:events) if result.success?

      raise ArgumentError, "persisted_events violate their dry-rb contract: #{result.errors.to_h.inspect}"
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
