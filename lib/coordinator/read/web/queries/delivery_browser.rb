# frozen_string_literal: true

module Coordinator::Read::Web::Queries
  class DeliveryBrowser
    def initialize(
      catalog_contract: Coordinator::Read::Web::Contracts::DeliveryBrowser::Catalog.new,
      candidate_contract: Coordinator::Read::Web::Contracts::DeliveryBrowser::Candidate.new,
      verification_contract: Coordinator::Read::Web::Contracts::DeliveryBrowser::Verification.new,
      merge_contract: Coordinator::Read::Web::Contracts::DeliveryBrowser::Merge.new,
      release_contract: Coordinator::Read::Web::Contracts::DeliveryBrowser::Release.new,
      batches_contract: Coordinator::Read::Web::Contracts::DeliveryBrowser::Batches.new,
      batch_contract: Coordinator::Read::Web::Contracts::DeliveryBrowser::Batch.new,
      repository: Coordinator::Read::Web::Repositories::DeliveryBrowser.new
    )
      @catalog_contract = catalog_contract
      @candidate_contract = candidate_contract
      @verification_contract = verification_contract
      @merge_contract = merge_contract
      @release_contract = release_contract
      @batches_contract = batches_contract
      @batch_contract = batch_contract
      @repository = repository
    end

    def catalog(input)
      values = validate(@catalog_contract, input)
      @repository.catalog(
        Coordinator::Read::Web::DeliveryBrowserQueryV1::Catalog.new(
          repository_id: values[:repository_id],
          first: values[:first] || 20,
          sort: values[:sort] || "newest_first",
          candidate_change_set_id: values[:candidate_change_set_id],
          candidate_checkpoint_kind: values[:candidate_checkpoint_kind],
          candidate_after_position: values[:candidate_after_position],
          candidate_after_id: values[:candidate_after_id],
          obligation_change_set_id: values[:obligation_change_set_id],
          obligation_status: values[:obligation_status],
          obligation_after_position: values[:obligation_after_position],
          obligation_after_id: values[:obligation_after_id],
          merge_after_position: values[:merge_after_position],
          merge_after_id: values[:merge_after_id],
          release_change_set_id: values[:release_change_set_id],
          release_status: values[:release_status],
          release_after_position: values[:release_after_position],
          release_after_id: values[:release_after_id]
        )
      )
    end

    def candidate(input)
      values = validate(@candidate_contract, input)
      @repository.candidate(
        Coordinator::Read::Web::DeliveryBrowserQueryV1::Candidate.new(
          repository_id: values[:repository_id],
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
          repository_id: values[:repository_id],
          obligation_id: values[:obligation_id],
          first: values[:first] || 20,
          after_evidence_position: values[:after_evidence_position],
          after_evidence_id: values[:after_evidence_id]
        )
      )
    end

    def merge(input)
      values = validate(@merge_contract, input)
      @repository.merge(
        Coordinator::Read::Web::DeliveryBrowserQueryV1::Merge.new(
          repository_id: values[:repository_id],
          merge_snapshot_id: values[:merge_snapshot_id],
          first: values[:first] || 20,
          after_authorization_position: values[:after_authorization_position],
          after_authorization_id: values[:after_authorization_id]
        )
      )
    end

    def release(input)
      values = validate(@release_contract, input)
      @repository.release(
        Coordinator::Read::Web::DeliveryBrowserQueryV1::Release.new(values.to_h)
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
          after_position: values[:after_position],
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

    def validate(contract, input)
      validated = contract.call(input)
      raise Coordinator::Read::Web::DeliveryBrowserQueryError, validated.errors.to_h if validated.failure?

      validated
    end
  end
end
