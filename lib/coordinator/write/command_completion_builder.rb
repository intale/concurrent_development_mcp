# frozen_string_literal: true

module Coordinator::Write
  class CommandCompletionBuilder
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
        next_actions: [
          NextAction.new(
            tool: "work_item_create",
            arguments: NextAction::ChangeSetArguments.new(change_set_id: command.change_set_id)
          )
        ],
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
        next_actions: [
          NextAction.new(
            tool: "work_item_create",
            arguments: NextAction::ChangeSetArguments.new(change_set_id: command.change_set_id)
          ),
          NextAction.new(
            tool: "change_set_activate",
            arguments: NextAction::ChangeSetArguments.new(change_set_id: command.change_set_id)
          )
        ],
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
        next_actions: [
          NextAction.new(
            tool: "change_set_activate",
            arguments: NextAction::ChangeSetArguments.new(change_set_id: command.change_set_id)
          )
        ],
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
        next_actions: [ NextAction.new(tool: "write_set_reserve", arguments: attempt_arguments) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def work_item_complete(command:, completion:, input_digest:, persisted_events:, completed_at:)
      attempt_arguments = NextAction::AttemptArguments.new(
        change_set_id: command.change_set_id,
        work_item_id: command.work_item_id,
        attempt_id: command.attempt_id
      )

      build_completion(
        command:,
        tool_name: "work_item_complete",
        summary: "Final Candidate selected; WorkItem and Attempt completed.",
        data: CommandReceiptData::WorkItemCompletion.new(
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          candidate_id: command.candidate_id,
          candidate_event: completion.candidate_event,
          selected_event: event_reference(persisted_events.fetch(0)),
          attempt_completed_event: event_reference(persisted_events.fetch(1)),
          work_item_completed_event: event_reference(persisted_events.fetch(2)),
          produced_outputs: completion.produced_outputs,
          completed_at: completion.completed_at
        ),
        next_actions: [ NextAction.new(tool: "coord_context", arguments: attempt_arguments) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def write_set_reserve(command:, reservation:, input_digest:, persisted_events:, completed_at:)
      attempt_arguments = NextAction::AttemptArguments.new(
        change_set_id: command.change_set_id,
        work_item_id: command.work_item_id,
        attempt_id: command.attempt_id
      )

      build_completion(
        command:,
        tool_name: "write_set_reserve",
        summary: "Write set reserved.",
        data: CommandReceiptData::LeaseSet.new(
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          repository_id: command.repository_id,
          lease_set_id: reservation.lease_set_id,
          policy_version: reservation.policy_version,
          acquired_at: reservation.reserved_at,
          expires_at: reservation.expires_at,
          resources: reservation.resources
        ),
        next_actions: [ NextAction.new(tool: "coord_context", arguments: attempt_arguments) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def write_set_expand(command:, expansion:, input_digest:, persisted_events:, completed_at:)
      attempt_arguments = NextAction::AttemptArguments.new(
        change_set_id: command.change_set_id,
        work_item_id: command.work_item_id,
        attempt_id: command.attempt_id
      )

      build_completion(
        command:,
        tool_name: "write_set_expand",
        summary: "Write set expanded.",
        data: CommandReceiptData::LeaseSetExpansion.new(
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          repository_id: command.repository_id,
          lease_set_id: expansion.lease_set_id,
          policy_version: expansion.policy_version,
          expanded_at: expansion.expanded_at,
          expires_at: expansion.expires_at,
          added_resources: expansion.added_resources,
          resource_count: expansion.resource_count
        ),
        next_actions: [ NextAction.new(tool: "coord_context", arguments: attempt_arguments) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def lease_renew(command:, renewal:, input_digest:, persisted_events:, completed_at:)
      attempt_arguments = NextAction::AttemptArguments.new(
        change_set_id: command.change_set_id,
        work_item_id: command.work_item_id,
        attempt_id: command.attempt_id
      )

      build_completion(
        command:,
        tool_name: "lease_renew",
        summary: "Lease set renewed.",
        data: CommandReceiptData::LeaseSetRenewal.new(
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          repository_id: renewal.repository_id,
          lease_set_id: renewal.lease_set_id,
          policy_version: renewal.policy_version,
          resources: renewal.resources,
          resource_count: renewal.resource_count,
          renewed_at: renewal.renewed_at,
          previous_expires_at: renewal.previous_expires_at,
          expires_at: renewal.expires_at
        ),
        next_actions: [ NextAction.new(tool: "coord_context", arguments: attempt_arguments) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def lease_release(command:, release:, input_digest:, persisted_events:, completed_at:)
      attempt_arguments = NextAction::AttemptArguments.new(
        change_set_id: command.change_set_id,
        work_item_id: command.work_item_id,
        attempt_id: command.attempt_id
      )

      build_completion(
        command:,
        tool_name: "lease_release",
        summary: "Lease set released.",
        data: CommandReceiptData::LeaseSetRelease.new(
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          repository_id: release.repository_id,
          lease_set_id: release.lease_set_id,
          policy_version: release.policy_version,
          resources: release.resources,
          resource_count: release.resource_count,
          previous_expires_at: release.previous_expires_at,
          released_at: release.released_at
        ),
        next_actions: [ NextAction.new(tool: "coord_context", arguments: attempt_arguments) ],
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
          resource_key_hash: expiration.resource_key_hash,
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

    def decision_interpretation_propose(command:, proposal:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "decision_interpretation_propose",
        summary: "Atomic decision interpretation proposed without activating policy.",
        data: CommandReceiptData::InterpretationProposal.new(
          interpretation_id: command.interpretation_id,
          source_message_id: command.source_message_id,
          assessment: proposal.assessment,
          proposed_at: proposal.proposed_at
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

    def decision_activate(command:, activation:, partitions:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "decision_activate",
        summary: "Accepted interpretation activated as authoritative policy.",
        data: CommandReceiptData::DecisionActivation.new(
          decision_id: command.decision_id,
          interpretation_id: command.interpretation_id,
          outcome: "activated",
          policy_status: "active",
          definition_digest: activation.definition_digest,
          slot: activation.slot,
          partitions:,
          activated_at: activation.activated_at
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
          previous_definition_digest: correction.previous_definition_digest,
          definition_digest: correction.definition.digest,
          correction_event:,
          slot: correction.slot,
          partitions:,
          corrected_at: correction.corrected_at
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

    def agent_choice_record(command:, acceptance:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "agent_choice_record",
        summary: "Agent choice recorded and accepted against authoritative Decision context.",
        data: CommandReceiptData::AgentChoice.new(
          choice_id: command.choice_id,
          choice_type: command.choice_type,
          outcome: "accepted",
          assessment_basis: acceptance.assessment.basis,
          context_digest: acceptance.context_digest,
          recorded_event: event_reference(persisted_events.fetch(0)),
          accepted_event: event_reference(persisted_events.fetch(1)),
          based_on_decisions: acceptance.assessment.based_on_decisions,
          warnings: acceptance.assessment.warnings,
          accepted_at: acceptance.accepted_at
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

    def candidate_submit(command:, submission:, input_digest:, persisted_events:, completed_at:)
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
          manifest_digest: submission.manifest_digest,
          build_context_digest: submission.build_context_digest,
          evidence_status: submission.evidence_status,
          candidate_event: event_reference(persisted_events.fetch(0)),
          submitted_at: submission.submitted_at
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

    def skill_publish(command:, publication:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "skill_publish",
        summary: "Skill revision published with an immutable asset snapshot.",
        data: CommandReceiptData::SkillPublication.new(
          skill_id: command.skill_id,
          name: command.name,
          scope: command.scope,
          revision: publication.revision,
          content_digest: command.content_digest,
          asset_count: command.assets.length,
          publication_event: event_reference(persisted_events.sole),
          published_at: publication.published_at
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

    def candidate_impact_surface_submit(
      command:,
      surface:,
      input_digest:,
      persisted_events:,
      completed_at:
    )
      build_completion(
        command:,
        tool_name: "candidate_impact_surface_submit",
        summary: "Candidate semantic-impact surface recorded as attributed, unverified evidence.",
        data: CommandReceiptData::CandidateImpactSurface.new(
          candidate_id: command.candidate_id,
          surface_digest: surface.surface_digest,
          evidence_revision: surface.evidence_revision,
          evidence_status: surface.evidence_status,
          surface_event: event_reference(persisted_events.fetch(0)),
          registration_event: event_reference(persisted_events.fetch(1)),
          derived_at: surface.derived_at
        ),
        next_actions: [
          NextAction.new(
            tool: "candidate_impact_get",
            arguments: NextAction::CandidateArguments.new(candidate_id: command.candidate_id)
          )
        ],
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
          claimed_at: claim.claimed_at,
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
      status = verification_status(persisted_events)
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
          outcome_event: persisted_events[1] ? event_reference(persisted_events.fetch(1)) : nil,
          submitted_at: evidence.submitted_at
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
          previous_status: waiver.previous_status,
          status: "waived",
          reason: waiver.reason,
          waiver_event: event_reference(persisted_events.sole),
          waived_at: waiver.waived_at
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

    def merge_snapshot_register(command:, snapshot:, input_digest:, persisted_events:, completed_at:)
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
          snapshot_digest: snapshot.snapshot_digest,
          evidence_status: snapshot.evidence_status,
          snapshot_event: event_reference(persisted_events.fetch(0)),
          registered_at: snapshot.registered_at
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

    def merge_verification_submit(command:, submission:, input_digest:, persisted_events:, completed_at:)
      verified_event = persisted_events.fetch(1, nil)
      status = if verified_event
                 "verified"
      elsif submission.assessment.conclusion == "passed"
                 "unverified"
      else
                 submission.assessment.conclusion
      end
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
          verification_input_digest: submission.verification_input_digest,
          submitted_event: event_reference(persisted_events.fetch(0)),
          verified_event: verified_event && event_reference(verified_event),
          submitted_at: submission.submitted_at
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

    def merge_authorization_request(command:, decision:, input_digest:, persisted_events:, completed_at:)
      outcome = decision.is_a?(Events::MergeAuthorizationGrantedV1) ? "granted" : "denied"
      build_completion(
        command:,
        tool_name: "merge_authorization_request",
        summary: merge_authorization_summary(outcome),
        data: CommandReceiptData::MergeAuthorization.new(
          authorization_id: decision.authorization_id,
          merge_snapshot_id: command.merge_snapshot_id,
          outcome:,
          decision_digest: decision.decision_digest,
          decision_event: event_reference(persisted_events.sole),
          reasons: decision.evaluation.reasons,
          obligations: decision.evaluation.obligations,
          work_item_progress: decision.evaluation.work_item_progress,
          decided_at: decision.decided_at
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

    def merge_observation_record(command:, observation:, input_digest:, persisted_events:, completed_at:)
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
          observation_digest: observation.observation_digest,
          evidence_status: observation.evidence_status,
          observation_event: event_reference(persisted_events.sole),
          observed_at: command.observed_at,
          recorded_at: observation.recorded_at
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

    def release_set_prepare(command:, preparation:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "release_set_prepare",
        summary: "Immutable ordered ReleaseSet prepared from exact current authorization evidence.",
        data: CommandReceiptData::ReleaseSetPreparation.new(
          release_set_id: preparation.release_set_id,
          change_set_id: preparation.change_set_id,
          ordered_members: preparation.ordered_members,
          release_digest: preparation.release_digest,
          policy_version: preparation.policy_version,
          prepared_event: event_reference(persisted_events.sole),
          prepared_at: preparation.prepared_at
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

    def release_repository_integration_record(command:, integration:, input_digest:, persisted_events:, completed_at:)
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
          integration_digest: integration.integration_digest,
          evidence_status: integration.evidence_status,
          integration_event: event_reference(persisted_events.sole),
          recorded_at: integration.recorded_at
        ),
        next_actions: [ release_set_next_action(command.release_set_id) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def release_verification_record(command:, verification:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "release_verification_record",
        summary: release_verification_summary(verification.evidence.outcome),
        data: CommandReceiptData::ReleaseSetVerification.new(
          release_set_id: verification.release_set_id,
          change_set_id: verification.change_set_id,
          attempt_number: verification.attempt_number,
          outcome: verification.evidence.outcome,
          integration_events: verification.integration_events,
          verification_digest: verification.verification_digest,
          evidence_status: verification.evidence_status,
          verification_event: event_reference(persisted_events.sole),
          recorded_at: verification.recorded_at
        ),
        next_actions: [ release_set_next_action(command.release_set_id) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def release_activation_record(command:, activation:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "release_activation_record",
        summary: "Attributed external ReleaseSet activation recorded; lifecycle completion is asynchronous.",
        data: CommandReceiptData::ReleaseSetActivation.new(
          release_set_id: activation.release_set_id,
          change_set_id: activation.change_set_id,
          verification_event: activation.verification_event,
          verification_digest: activation.verification_digest,
          activation_digest: activation.activation_digest,
          evidence_status: activation.evidence_status,
          activation_event: event_reference(persisted_events.sole),
          recorded_at: activation.recorded_at
        ),
        next_actions: [ release_set_next_action(command.release_set_id) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def release_compensation_request(command:, request:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "release_compensation_request_policy",
        summary: "ReleaseSet compensation requested for the exact successful integrations.",
        data: CommandReceiptData::ReleaseSetCompensationRequest.new(
          release_set_id: request.release_set_id,
          change_set_id: request.change_set_id,
          trigger_event: request.trigger_event,
          trigger_kind: request.trigger_kind,
          successful_integrations: request.successful_integrations,
          compensation_request_event: event_reference(persisted_events.sole),
          requested_at: request.requested_at
        ),
        next_actions: [ release_set_next_action(command.release_set_id) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def release_activated_complete(command:, completion:, input_digest:, persisted_events:, completed_at:)
      release_set_completion(
        command:,
        completion:,
        tool_name: "release_activated_complete_policy",
        summary: "Activated ReleaseSet lifecycle completed.",
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def release_compensation_complete(command:, completion:, input_digest:, persisted_events:, completed_at:)
      release_set_completion(
        command:,
        completion:,
        tool_name: "release_compensation_complete",
        summary: "Attributed external compensation evidence completed the ReleaseSet lifecycle.",
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def dependency_satisfaction_policy(command:, satisfaction:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "dependency_satisfaction_policy",
        summary: "WorkItem dependency satisfied from exact coordination evidence.",
        data: CommandReceiptData::DependencySatisfaction.new(
          change_set_id: satisfaction.change_set_id,
          dependency_id: satisfaction.dependency_id,
          consumer_work_item_id: satisfaction.consumer_work_item_id,
          source_event: satisfaction.source_event,
          satisfaction_event: event_reference(persisted_events.fetch(0)),
          readiness_event: persisted_events[1] && event_reference(persisted_events.fetch(1)),
          satisfied_at: satisfaction.satisfied_at
        ),
        next_actions: [],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def change_set_completion_policy(command:, completion:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "change_set_completion_policy",
        summary: "ChangeSet completed from exact WorkItem and release evidence.",
        data: CommandReceiptData::ChangeSetCompletion.new(
          change_set_id: completion.change_set_id,
          work_item_completions: completion.work_item_completions,
          release_set_completion_event: completion.release_set_completion_event,
          completion_event: event_reference(persisted_events.sole),
          completed_at: completion.completed_at
        ),
        next_actions: [],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    private

    def release_set_completion(command:, completion:, tool_name:, summary:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name:,
        summary:,
        data: CommandReceiptData::ReleaseSetCompletion.new(
          release_set_id: completion.release_set_id,
          change_set_id: completion.change_set_id,
          outcome: completion.outcome,
          source_event: completion.source_event,
          completion_digest: completion.completion_digest,
          completion_event: event_reference(persisted_events.sole),
          completed_at: completion.completed_at
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

      Events::CommandCompletedV1.new(
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
