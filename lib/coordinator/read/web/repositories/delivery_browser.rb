# frozen_string_literal: true

module Coordinator::Read::Web::Repositories
  class DeliveryBrowser
    def initialize(
      candidates: Coordinator::Read::Repositories::Candidates.new,
      candidate_impacts: Coordinator::Read::Repositories::CandidateImpacts.new
    )
      @candidates = candidates
      @candidate_impacts = candidate_impacts
    end

    def candidates(query)
      repository_ids = project_repository_ids(query.project_scope)
      return unless repository_ids

      candidate_page(query, repository_ids)
    end

    def obligations(query)
      repository_ids = project_repository_ids(query.project_scope)
      return unless repository_ids

      verification_page(query, repository_ids)
    end

    def merges(query)
      repository_ids = project_repository_ids(query.project_scope)
      return unless repository_ids

      merge_page(query, repository_ids)
    end

    def releases(query)
      repository_ids = project_repository_ids(query.project_scope)
      return unless repository_ids

      release_page(query, repository_ids)
    end

    def candidate(query)
      repository_ids = project_repository_ids(query.project_scope)
      return unless repository_ids

      record = Coordinator::Read::Candidate.find_by(
        repository_id: repository_ids,
        candidate_id: query.candidate_id
      )
      return unless record

      impacts = @candidate_impacts.page(
        Coordinator::Read::CandidateImpactGetQueryV1.new(
          candidate_id: query.candidate_id,
          direction: query.direction,
          after_global_position: query.after_impact_position,
          limit: query.first
        )
      )
      Coordinator::Read::Web::DeliveryBrowserV1::CandidateDetail.new(
        candidate: @candidates.fetch(query.candidate_id),
        impacts:
      )
    end

    def verification(query)
      repository_ids = project_repository_ids(query.project_scope)
      return unless repository_ids

      record = verification_for_project(repository_ids)
        .find_by(obligation_id: query.obligation_id)
      return unless record

      obligation = record.obligation
      Coordinator::Read::Web::DeliveryBrowserV1::VerificationDetail.new(
        obligation: build_verification_summary(record),
        required_evidence: obligation.fetch("required_evidence"),
        reasons: obligation.fetch("reasons").map do |reason|
          Coordinator::Read::Web::DeliveryBrowserV1::VerificationReason.new(
            kind: reason.fetch("kind"),
            matches: reason.fetch("matches")
          )
        end,
        evidence: evidence_page(record, query)
      )
    end

    def merge(query)
      repository_ids = project_repository_ids(query.project_scope)
      return unless repository_ids

      record = Coordinator::Read::MergeSnapshot.find_by(
        repository_id: repository_ids,
        merge_snapshot_id: query.merge_snapshot_id
      )
      return unless record

      Coordinator::Read::Web::DeliveryBrowserV1::MergeDetail.new(
        snapshot: build_merge_summary(record),
        candidates: record.ordered_candidates.map { build_merge_candidate(_1) },
        authorizations: authorization_page(record, query)
      )
    end

    def release(query)
      repository_ids = project_repository_ids(query.project_scope)
      return unless repository_ids

      record = release_for_project(repository_ids)
        .find_by(release_set_id: query.release_set_id)
      return unless record

      Coordinator::Read::Web::DeliveryBrowserV1::ReleaseDetail.new(
        release_set: build_release_summary(record),
        members: record.ordered_members.map { build_release_member(_1) },
        integrations: record.integrations.map { build_release_integration(_1) },
        verification_attempt_count: record.verifications.length,
        activated: record.activation.present?,
        compensation_requested: record.compensation_request.present?,
        completion_outcome: record.completion&.fetch("outcome", nil)
      )
    end

    def batches(query)
      relation = Coordinator::Read::OperationBatch.where.not(
        created_global_position: nil,
        total: nil
      )
      relation = relation.where(target_tool: query.target_tool) if query.target_tool
      relation = relation.where(status: query.status) if query.status
      rows, has_more = timeline_rows(
        relation:,
        position_column: :created_global_position,
        id_column: :batch_id,
        after_position: query.after_position,
        after_id: query.after_id,
        sort: query.sort,
        limit: query.first
      )
      Coordinator::Read::Web::DeliveryBrowserV1::OperationBatchPage.new(
        items: rows.map { build_batch_summary(_1) },
        next_cursor: timeline_cursor(rows.last, :created_global_position, :batch_id, has_more:),
        has_more:
      )
    end

    def batch(query)
      record = Coordinator::Read::OperationBatch.find_by(batch_id: query.batch_id)
      return unless record&.total

      relation = Coordinator::Read::OperationBatchItem.where(batch_id: query.batch_id)
      relation = relation.where("item_index > ?", query.after_index) if query.after_index
      rows = relation.order(:item_index).limit(query.first + 1).to_a
      has_more = rows.length > query.first
      selected = rows.first(query.first)
      outcomes = Coordinator::Read::OperationBatchOutcome.where(
        batch_id: query.batch_id,
        item_index: selected.map(&:item_index)
      ).index_by(&:item_index)
      items = selected.map { build_batch_item(_1, outcomes[_1.item_index], record.terminal_kind) }

      Coordinator::Read::Web::DeliveryBrowserV1::OperationBatchDetail.new(
        batch: build_batch_summary(record),
        items: Coordinator::Read::Web::DeliveryBrowserV1::OperationBatchItemPage.new(
          items:,
          next_index: has_more ? items.last.index : nil,
          has_more:
        )
      )
    end

    private

    def project_repository_ids(project_scope)
      ids = Coordinator::Read::Repository.where(scope: project_scope).order(:repository_id).pluck(:repository_id)
      ids unless ids.empty?
    end

    def candidate_page(query, repository_ids)
      relation = Coordinator::Read::Candidate.where(repository_id: repository_ids)
      relation = relation.where(change_set_id: query.change_set_id) if query.change_set_id
      relation = relation.where(checkpoint_kind: query.checkpoint_kind) if query.checkpoint_kind
      rows, has_more = timeline_rows(
        relation:,
        position_column: :submitted_global_position,
        id_column: :candidate_id,
        after_position: query.after_position,
        after_id: query.after_id,
        sort: query.sort,
        limit: query.first
      )
      summaries = @candidates.summaries(rows.map(&:candidate_id))
      Coordinator::Read::Web::DeliveryBrowserV1::CandidatePage.new(
        items: rows.map { summaries.fetch(_1.candidate_id) },
        next_cursor: timeline_cursor(rows.last, :submitted_global_position, :candidate_id, has_more:),
        has_more:
      )
    end

    def verification_page(query, repository_ids)
      relation = verification_for_project(repository_ids)
      relation = relation.where(change_set_id: query.change_set_id) if query.change_set_id
      relation = relation.where(status: query.status) if query.status
      rows, has_more = timeline_rows(
        relation:,
        position_column: :event_global_position,
        id_column: :obligation_id,
        after_position: query.after_position,
        after_id: query.after_id,
        sort: query.sort,
        limit: query.first
      )
      Coordinator::Read::Web::DeliveryBrowserV1::VerificationPage.new(
        items: rows.map { build_verification_summary(_1) },
        next_cursor: timeline_cursor(rows.last, :event_global_position, :obligation_id, has_more:),
        has_more:
      )
    end

    def merge_page(query, repository_ids)
      rows, has_more = timeline_rows(
        relation: Coordinator::Read::MergeSnapshot.where(repository_id: repository_ids),
        position_column: :registered_global_position,
        id_column: :merge_snapshot_id,
        after_position: query.after_position,
        after_id: query.after_id,
        sort: query.sort,
        limit: query.first
      )
      Coordinator::Read::Web::DeliveryBrowserV1::MergePage.new(
        items: rows.map { build_merge_summary(_1) },
        next_cursor: timeline_cursor(rows.last, :registered_global_position, :merge_snapshot_id, has_more:),
        has_more:
      )
    end

    def release_page(query, repository_ids)
      relation = release_for_project(repository_ids)
      relation = relation.where(change_set_id: query.change_set_id) if query.change_set_id
      relation = relation.where(status: query.status) if query.status
      rows, has_more = timeline_rows(
        relation:,
        position_column: :prepared_global_position,
        id_column: :release_set_id,
        after_position: query.after_position,
        after_id: query.after_id,
        sort: query.sort,
        limit: query.first
      )
      Coordinator::Read::Web::DeliveryBrowserV1::ReleasePage.new(
        items: rows.map { build_release_summary(_1) },
        next_cursor: timeline_cursor(rows.last, :prepared_global_position, :release_set_id, has_more:),
        has_more:
      )
    end

    def verification_for_project(repository_ids)
      Coordinator::Read::VerificationObligation.where(
        "source_repository_id IN (:repository_ids) OR target_repository_id IN (:repository_ids)",
        repository_ids:
      )
    end

    def release_for_project(repository_ids)
      Coordinator::Read::ReleaseSet.where(
        <<~SQL.squish,
          EXISTS (
            SELECT 1
            FROM jsonb_array_elements(release_sets.ordered_members) AS member
            WHERE member ->> 'repository_id' IN (?)
          )
        SQL
        repository_ids
      )
    end

    def evidence_page(record, query)
      relation = Coordinator::Read::VerificationObligationEvidenceItem.where(
        obligation_id: record.obligation_id
      )
      if query.after_evidence_position && query.after_evidence_id
        relation = relation.where(
          "event_global_position > :position OR " \
          "(event_global_position = :position AND evidence_id > :identifier)",
          position: query.after_evidence_position,
          identifier: query.after_evidence_id
        )
      end
      rows = relation.order(:event_global_position, :evidence_id).limit(query.first + 1).to_a
      has_more = rows.length > query.first
      selected = rows.first(query.first)
      Coordinator::Read::Web::DeliveryBrowserV1::EvidencePage.new(
        items: selected.map { build_evidence(_1) },
        next_cursor: timeline_cursor(selected.last, :event_global_position, :evidence_id, has_more:),
        has_more:
      )
    end

    def authorization_page(record, query)
      relation = Coordinator::Read::MergeAuthorization.where(
        merge_snapshot_id: record.merge_snapshot_id
      )
      if query.after_authorization_position && query.after_authorization_id
        relation = relation.where(
          "source_global_position > :position OR " \
          "(source_global_position = :position AND authorization_id > :identifier)",
          position: query.after_authorization_position,
          identifier: query.after_authorization_id
        )
      end
      rows = relation.order(:source_global_position, :authorization_id).limit(query.first + 1).to_a
      has_more = rows.length > query.first
      selected = rows.first(query.first)
      Coordinator::Read::Web::DeliveryBrowserV1::AuthorizationPage.new(
        items: selected.map { build_authorization(_1) },
        next_cursor: timeline_cursor(selected.last, :source_global_position, :authorization_id, has_more:),
        has_more:
      )
    end

    def timeline_rows(
      relation:,
      position_column:,
      id_column:,
      after_position:,
      after_id:,
      sort:,
      limit:
    )
      direction = sort == "newest_first" ? :desc : :asc
      comparator = direction == :desc ? "<" : ">"
      if after_position && after_id
        relation = relation.where(
          "#{position_column} #{comparator} :position OR " \
          "(#{position_column} = :position AND #{id_column} #{comparator} :identifier)",
          position: after_position,
          identifier: after_id
        )
      end
      rows = relation.order(position_column => direction, id_column => direction).limit(limit + 1).to_a
      [ rows.first(limit), rows.length > limit ]
    end

    def timeline_cursor(record, position_column, id_column, has_more:)
      return unless has_more && record

      Coordinator::Read::Web::DeliveryBrowserV1::TimelineCursor.new(
        position: record.public_send(position_column),
        id: record.public_send(id_column)
      )
    end

    def build_verification_summary(record)
      Coordinator::Read::Web::DeliveryBrowserV1::VerificationSummary.new(
        obligation_id: record.obligation_id,
        kind: record.kind,
        status: record.status,
        change_set_id: record.change_set_id,
        source_candidate_id: record.source_candidate_id,
        target_candidate_id: record.target_candidate_id,
        source_repository_id: record.source_repository_id,
        target_repository_id: record.target_repository_id,
        enforcement: record.enforcement,
        claimant_id: record.claimant_id,
        claim_expires_at: record.claim_expires_at_domain&.utc&.iso8601(6),
        evidence_count: record.evidence_count,
        passed_evidence_kinds: record.passed_evidence_kinds,
        missing_evidence_kinds: record.missing_evidence_kinds,
        created_at: record.created_at_domain.utc.iso8601(6)
      )
    end

    def build_evidence(record)
      Coordinator::Read::Web::DeliveryBrowserV1::VerificationEvidence.new(
        evidence_id: record.evidence_id,
        evidence_kind: record.evidence_kind,
        conclusion: record.conclusion,
        assessment_input_digest: record.assessment_input_digest,
        result_digest: record.result_digest,
        produced_at: record.produced_at_domain.utc.iso8601(6),
        submitted_at: record.submitted_at_domain.utc.iso8601(6),
        global_position: record.event_global_position
      )
    end

    def build_merge_summary(record)
      Coordinator::Read::Web::DeliveryBrowserV1::MergeSummary.new(
        merge_snapshot_id: record.merge_snapshot_id,
        repository_id: record.repository_id,
        target_branch: record.target_branch,
        target_base_commit_oid: record.target_base_commit_oid,
        merge_commit_oid: record.merge_commit_oid,
        candidate_count: record.ordered_candidates.length,
        verification_status: record.verification_status,
        evidence_status: record.evidence_status,
        produced_at: record.produced_at_domain.utc.iso8601(6)
      )
    end

    def build_authorization(record)
      Coordinator::Read::Web::DeliveryBrowserV1::AuthorizationSummary.new(
        authorization_id: record.authorization_id,
        merge_snapshot_id: record.merge_snapshot_id,
        outcome: record.outcome,
        policy_version: record.policy_version,
        input_digest: record.input_digest,
        decision_digest: record.decision_digest,
        reason_count: record.evaluation.fetch("reasons", []).length,
        decided_at: record.decided_at_domain.utc.iso8601(6)
      )
    end

    def build_merge_candidate(attributes)
      Coordinator::Read::Web::DeliveryBrowserV1::MergeCandidate.new(
        candidate_id: attributes.fetch("candidate_id"),
        change_set_id: attributes.fetch("change_set_id"),
        work_item_id: attributes.fetch("work_item_id"),
        attempt_id: attributes.fetch("attempt_id"),
        base_commit_oid: attributes.fetch("base_commit_oid"),
        head_commit_oid: attributes.fetch("head_commit_oid"),
        manifest_digest: attributes.fetch("manifest_digest")
      )
    end

    def build_release_summary(record)
      repository_ids = record.ordered_members.map { _1.fetch("repository_id") }.uniq
      Coordinator::Read::Web::DeliveryBrowserV1::ReleaseSummary.new(
        release_set_id: record.release_set_id,
        change_set_id: record.change_set_id,
        repository_ids:,
        member_count: record.ordered_members.length,
        status: record.status,
        verification_status: record.verification_status,
        release_digest: record.release_digest,
        prepared_at: record.prepared_at_domain.utc.iso8601(6)
      )
    end

    def build_release_member(attributes)
      Coordinator::Read::Web::DeliveryBrowserV1::ReleaseMember.new(
        position: attributes.fetch("position"),
        repository_id: attributes.fetch("repository_id"),
        target_branch: attributes.fetch("target_branch"),
        merge_snapshot_id: attributes.fetch("merge_snapshot_id"),
        change_set_id: attributes.fetch("change_set_id"),
        merge_commit_oid: attributes.fetch("merge_commit_oid"),
        candidate_count: attributes.fetch("ordered_candidates").length
      )
    end

    def build_release_integration(attributes)
      Coordinator::Read::Web::DeliveryBrowserV1::ReleaseIntegration.new(
        repository_id: attributes.fetch("repository_id"),
        attempt_id: attributes.fetch("attempt_id"),
        attempt_number: attributes.fetch("attempt_number"),
        outcome: attributes.fetch("outcome"),
        failure_code: attributes.dig("failure", "code"),
        recorded_at: attributes.fetch("recorded_at")
      )
    end

    def build_batch_summary(record)
      unprocessed = record.total - record.succeeded_count - record.rejected_count
      Coordinator::Read::Web::DeliveryBrowserV1::OperationBatchSummary.new(
        batch_id: record.batch_id,
        target_tool: record.target_tool,
        status: record.status,
        total: record.total,
        succeeded: record.succeeded_count,
        rejected: record.rejected_count,
        pending: record.terminal_kind ? 0 : unprocessed,
        not_run: record.terminal_kind == "cancelled" ? unprocessed : 0,
        manifest_digest: record.manifest_digest,
        created_at: record.created_at_domain.utc.iso8601(6)
      )
    end

    def build_batch_item(item, outcome, terminal_kind)
      result = outcome&.result
      Coordinator::Read::Web::DeliveryBrowserV1::OperationBatchItem.new(
        index: item.item_index,
        target_tool: item.target_tool,
        command_id: item.command_id,
        canonical_input_digest: item.canonical_input_digest,
        status: outcome&.status || (terminal_kind == "cancelled" ? "not_run" : "pending"),
        outcome_status: result&.fetch("status", nil),
        outcome_summary: result&.fetch("summary", nil),
        outcome_code: result&.dig("data", "code"),
        finished_at: outcome&.finished_at_domain&.utc&.iso8601(6)
      )
    end
  end
end
