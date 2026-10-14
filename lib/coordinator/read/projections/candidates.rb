# frozen_string_literal: true

module Coordinator::Read::Projections
  class Candidates
    PROPERTY_COLUMNS = {
      "CandidateAssignedToAttempt" => %i[change_set_id work_item_id attempt_id],
      "CandidateAssignedToRepository" => %i[repository_id], "CandidateTargetBranchSelected" => %i[target_branch],
      "CandidateCommitRangeDeclared" => %i[object_format base_commit_oid head_commit_oid],
      "CandidateCheckpointKindSelected" => %i[checkpoint_kind], "CandidateWorkIntentionSetAssigned" => %i[intention_set_id]
    }.freeze
    def initialize(headers:, changed:, observed:, keys:)
      @headers, @changed, @observed, @keys = headers, changed, observed, keys
    end

    def apply(event, submission: nil, surface: nil)
      id = event.data.fetch("candidate_id")
      case event.type
      when "CandidateSubmitted"
        attributes = submission_attributes(submission)
        @headers.insert(attributes.merge(build_context_digest: nil, build_context: nil,
          created_at: submission.created_event.created_at, updated_at: event.created_at).merge(attributes))
        @headers.assign(attributes)
        manifest_members(submission, time: event.created_at)
        observed_members(submission, time: event.created_at) if submission.build_context
      when "CandidateImpactSurfaceAssigned"
        attributes = surface.surface.merge(policy_version: surface.event.metadata.fetch("policy_version"),
          surface_digest: surface.event.metadata.fetch("surface_digest"),
          manifest_digest: surface.event.metadata.fetch("manifest_digest"), build_context_digest: surface.event.metadata["build_context_digest"],
          analyzer: surface.event.metadata.fetch("analyzer"), evidence_status: "attributed_unverified").except(:candidate_id, :surface_id)
        @headers.assign({ candidate_id: id, impact_surface: attributes }.merge(Source.evidence(surface.event, prefix: :impact)))
        %i[produces consumes may_affect assumes].each do |direction|
          surface.surface.fetch(direction).each do |entry|
            member(@keys, { candidate_id: id, direction: direction.to_s, impact_key: entry.fetch(:impact_key) },
              { change_set_id: submission.change_set_id }, time: event.created_at)
          end
        end
      else
        columns = PROPERTY_COLUMNS[event.type]
        @headers.assign(Coordinator::Read::CommandResults::Source.document(event.data).slice(:candidate_id, *columns)) if columns
      end
      @headers.touch({ candidate_id: id }, time: event.created_at)
      nil
    end

    private

    def submission_attributes(source)
      attributes = { candidate_id: source.candidate_id, change_set_id: source.change_set_id, work_item_id: source.work_item_id,
        attempt_id: source.attempt_id, agent_id: source.agent_id, repository_id: source.repository_id,
        target_branch: source.target_branch, object_format: source.object_format, base_commit_oid: source.base_commit_oid,
        head_commit_oid: source.head_commit_oid, checkpoint_kind: source.checkpoint_kind, intention_set_id: source.intention_set_id,
        intention_policy_version: Coordinator::Write::WorkIntentionPolicyV1::VERSION, intentions: source.intentions,
        manifest_digest: source.manifest_digest, evidence_status: source.evidence_status,
        manifest: source.manifest.slice(:files).merge(policy_version: source.manifest_event.metadata.fetch("policy_version"),
          digest: source.manifest_digest, collector: source.manifest_event.metadata.fetch("collector")) }
        .merge(Source.evidence(source.submitted_event, prefix: :submitted)).merge(Source.evidence(source.manifest_event, prefix: :manifest))
      return attributes unless source.build_context_event

      attributes.merge(build_context_digest: source.build_context_digest,
        build_context: source.build_context.slice(:inputs, :environment).merge(
          policy_version: source.build_context_event.metadata.fetch("policy_version"), digest: source.build_context_digest,
          dependency_graph_digest: source.build_context_event.metadata["dependency_graph_digest"],
          test_environment_digest: source.build_context_event.metadata["test_environment_digest"],
          collector: source.build_context_event.metadata.fetch("collector")))
        .merge(Source.evidence(source.build_context_event, prefix: :build_context))
    end

    def manifest_members(source, time:)
      source.manifest.fetch(:files).flat_map do |file|
        case file.fetch(:status)
        when "added", "copied" then [ file[:new_path] ]
        when "renamed" then [ file[:old_path], file[:new_path] ]
        else [ file[:old_path] ]
        end
      end.compact.uniq.each do |path|
        member(@changed, { candidate_id: source.candidate_id, path: },
          { change_set_id: source.change_set_id, repository_id: source.repository_id }, time:)
      end
    end

    def observed_members(source, time:)
      source.build_context.fetch(:inputs).map { _1.fetch(:path) }.uniq.each do |path|
        member(@observed, { candidate_id: source.candidate_id, path: },
          { change_set_id: source.change_set_id, repository_id: source.repository_id }, time:)
      end
    end

    def member(patches, identity, attributes, time:)
      attributes = identity.merge(attributes)
      patches.insert(attributes.merge(created_at: time, updated_at: time))
      patches.assign(attributes)
      patches.touch(identity, time:)
    end
  end
end
