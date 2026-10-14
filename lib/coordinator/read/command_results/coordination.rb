# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class Coordination
      TOOLS = %w[change_set_create work_item_create work_item_dependency_declare change_set_activate
        work_item_acquire work_item_complete guidance_record candidate_submit candidate_impact_surface_submit].freeze

      def call(source)
        case source.tool_name
        when "change_set_create"
          source.presentation("ChangeSet created.", source.values(:change_set_id))
        when "work_item_create"
          source.presentation("WorkItem created.", source.values(:change_set_id, :work_item_id))
        when "work_item_dependency_declare"
          source.presentation("WorkItem dependency declared.", source.values(:change_set_id, :dependency_id))
        when "change_set_activate"
          source.presentation("ChangeSet activated.", source.values(:change_set_id),
            next_actions: [ source.action("coord_context", **source.values(:change_set_id)) ])
        when "work_item_acquire"
          source.presentation("WorkItem acquired and Attempt started.", source.values(:change_set_id, :work_item_id, :attempt_id))
        when "work_item_complete" then work_item_completion(source)
        when "guidance_record"
          source.presentation("Guidance evidence recorded without activating policy.",
            source.values(:message_id, :conversation_id, :source).merge(policy_status: "evidence_only", recorded_at: source.completed_at),
            next_actions: [ source.action("guidance_get", message_id: source.input.fetch(:message_id)) ])
        when "candidate_submit" then candidate(source)
        when "candidate_impact_surface_submit" then impact_surface(source)
        end
      end

      private

      def work_item_completion(source)
        selected = source.event("WorkItemCandidateSelected")
        source.presentation("Final Candidate selected; WorkItem and Attempt completed.",
          source.values(:change_set_id, :work_item_id, :attempt_id, :candidate_id, :produced_outputs).merge(
            candidate_event: source.fact("WorkItemCandidateSelected").fetch(:candidate_event),
            selected_event: source.reference(selected), attempt_completed_event: source.reference(source.event("AttemptCompleted")),
            work_item_completed_event: source.reference(source.event("WorkItemCompleted")), completed_at: source.completed_at
          ), next_actions: [ source.action("coord_context", **source.values(:change_set_id)) ])
      end

      def candidate(source)
        event = source.event("CandidateSubmitted")
        source.presentation("Candidate submitted with attributed, unverified source evidence.",
          source.values(:candidate_id, :change_set_id, :work_item_id, :attempt_id, :repository_id, :target_branch,
            :object_format, :base_commit_oid, :head_commit_oid, :checkpoint_kind).merge(
            manifest_digest: source.input.fetch(:change_manifest).fetch(:digest),
            build_context_digest: source.input[:build_context]&.fetch(:digest), evidence_status: "attributed_unverified",
            candidate_event: source.reference(event), submitted_at: source.timestamp(event)
          ), next_actions: [ source.action("candidate_get", **source.values(:candidate_id)) ])
      end

      def impact_surface(source)
        event = source.event("CandidateImpactSurfaceDerived")
        source.presentation("Candidate semantic-impact surface recorded as attributed, unverified evidence.", {
          candidate_id: source.input.fetch(:candidate_id), surface_id: source.data(event).fetch(:surface_id),
          surface_digest: source.input.fetch(:surface).fetch(:digest), evidence_revision: event.data.fetch("evidence_revision"),
          evidence_status: "attributed_unverified", surface_event: source.reference(event),
          registration_event: source.reference(source.event("CandidateImpactSurfaceAssigned")), derived_at: source.timestamp(event)
        })
      end
    end
  end
end
