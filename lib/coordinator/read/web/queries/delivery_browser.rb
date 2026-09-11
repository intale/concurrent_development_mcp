# frozen_string_literal: true

module Coordinator::Read::Web::Queries
  class DeliveryBrowser
    def initialize(
      candidates_contract: Coordinator::Read::Web::Contracts::DeliveryBrowser::Candidates.new,
      obligations_contract: Coordinator::Read::Web::Contracts::DeliveryBrowser::Obligations.new,
      merges_contract: Coordinator::Read::Web::Contracts::DeliveryBrowser::Merges.new,
      releases_contract: Coordinator::Read::Web::Contracts::DeliveryBrowser::Releases.new,
      candidate_contract: Coordinator::Read::Web::Contracts::DeliveryBrowser::Candidate.new,
      verification_contract: Coordinator::Read::Web::Contracts::DeliveryBrowser::Verification.new,
      merge_contract: Coordinator::Read::Web::Contracts::DeliveryBrowser::Merge.new,
      release_contract: Coordinator::Read::Web::Contracts::DeliveryBrowser::Release.new,
      batches_contract: Coordinator::Read::Web::Contracts::DeliveryBrowser::Batches.new,
      batch_contract: Coordinator::Read::Web::Contracts::DeliveryBrowser::Batch.new,
      project_reference: Coordinator::Read::Web::ProjectReference.new,
      repository: Coordinator::Read::Web::Repositories::DeliveryBrowser.new
    )
      @candidates_contract = candidates_contract
      @obligations_contract = obligations_contract
      @merges_contract = merges_contract
      @releases_contract = releases_contract
      @candidate_contract = candidate_contract
      @verification_contract = verification_contract
      @merge_contract = merge_contract
      @release_contract = release_contract
      @batches_contract = batches_contract
      @batch_contract = batch_contract
      @project_reference = project_reference
      @repository = repository
    end

    def candidates(input)
      values = validate(@candidates_contract, input)
      @repository.candidates(
        Coordinator::Read::Web::DeliveryBrowserQueryV1::Candidates.new(
          project_scope: project_scope(values),
          first: values[:first] || 20,
          sort: values[:sort] || "newest_first",
          change_set_id: values[:change_set_id],
          checkpoint_kind: values[:checkpoint_kind],
          after_updated_at: values[:after_updated_at],
          after_id: values[:after_id]
        )
      )
    end

    def obligations(input)
      values = validate(@obligations_contract, input)
      @repository.obligations(
        Coordinator::Read::Web::DeliveryBrowserQueryV1::Obligations.new(
          project_scope: project_scope(values),
          first: values[:first] || 20,
          sort: values[:sort] || "newest_first",
          change_set_id: values[:change_set_id],
          status: values[:status],
          after_updated_at: values[:after_updated_at],
          after_id: values[:after_id]
        )
      )
    end

    def merges(input)
      values = validate(@merges_contract, input)
      @repository.merges(
        Coordinator::Read::Web::DeliveryBrowserQueryV1::Merges.new(
          project_scope: project_scope(values),
          first: values[:first] || 20,
          sort: values[:sort] || "newest_first",
          after_updated_at: values[:after_updated_at],
          after_id: values[:after_id]
        )
      )
    end

    def releases(input)
      values = validate(@releases_contract, input)
      @repository.releases(
        Coordinator::Read::Web::DeliveryBrowserQueryV1::Releases.new(
          project_scope: project_scope(values),
          first: values[:first] || 20,
          sort: values[:sort] || "newest_first",
          change_set_id: values[:change_set_id],
          status: values[:status],
          after_updated_at: values[:after_updated_at],
          after_id: values[:after_id]
        )
      )
    end

    def candidate(input)
      values = validate(@candidate_contract, input)
      @repository.candidate(
        Coordinator::Read::Web::DeliveryBrowserQueryV1::Candidate.new(
          project_scope: project_scope(values),
          candidate_id: values[:candidate_id],
          direction: values[:direction] || "outgoing",
          first: values[:first] || 20,
          after_impact_position: values[:after_impact_position]
        )
      )
    end

    def verification(input)
      values = validate(@verification_contract, input)
      @repository.verification(
        Coordinator::Read::Web::DeliveryBrowserQueryV1::Verification.new(
          project_scope: project_scope(values),
          obligation_id: values[:obligation_id],
          first: values[:first] || 20,
          after_evidence_updated_at: values[:after_evidence_updated_at],
          after_evidence_id: values[:after_evidence_id]
        )
      )
    end

    def merge(input)
      values = validate(@merge_contract, input)
      @repository.merge(
        Coordinator::Read::Web::DeliveryBrowserQueryV1::Merge.new(
          project_scope: project_scope(values),
          merge_snapshot_id: values[:merge_snapshot_id],
          first: values[:first] || 20,
          after_authorization_updated_at: values[:after_authorization_updated_at],
          after_authorization_id: values[:after_authorization_id]
        )
      )
    end

    def release(input)
      values = validate(@release_contract, input)
      @repository.release(
        Coordinator::Read::Web::DeliveryBrowserQueryV1::Release.new(
          project_scope: project_scope(values),
          release_set_id: values[:release_set_id]
        )
      )
    end

    def batches(input)
      values = validate(@batches_contract, input)
      @repository.batches(
        Coordinator::Read::Web::DeliveryBrowserQueryV1::Batches.new(
          first: values[:first] || 20,
          sort: values[:sort] || "newest_first",
          target_tool: values[:target_tool],
          status: values[:status],
          after_updated_at: values[:after_updated_at],
          after_id: values[:after_id]
        )
      )
    end

    def batch(input)
      values = validate(@batch_contract, input)
      @repository.batch(
        Coordinator::Read::Web::DeliveryBrowserQueryV1::Batch.new(
          batch_id: values[:batch_id],
          first: values[:first] || 50,
          after_index: values[:after_index]
        )
      )
    end

    private

    def project_scope(values)
      @project_reference.decode(values[:project_ref])
    end

    def validate(contract, input)
      validated = contract.call(input)
      raise Coordinator::Read::Web::DeliveryBrowserQueryError, validated.errors.to_h if validated.failure?

      validated
    end
  end
end
