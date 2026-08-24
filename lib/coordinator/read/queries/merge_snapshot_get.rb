# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class MergeSnapshotGet < Dry::Operation
      def initialize(contract: Contracts::MergeSnapshotGet.new, snapshots: Repositories::MergeSnapshots.new)
        @contract = contract
        @snapshots = snapshots
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = MergeSnapshotGetQueryV1.new(merge_snapshot_id: validated[:merge_snapshot_id])
        snapshot = @snapshots.fetch(query.merge_snapshot_id)
        return not_found_result(query.merge_snapshot_id) unless snapshot

        QueryResultV1.new(
          status: "ok",
          summary: "Latest available attributed merge snapshot; external Git composition is unverified.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::MergeSnapshotData.new(snapshot:),
          warnings: [ "This view may lag the authoritative event store." ],
          next_actions: []
        )
      end

      private

      def not_found_result(merge_snapshot_id)
        QueryResultV1.new(
          status: "not_found",
          summary: "No projected merge snapshot is currently available for this ID.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "merge_snapshot_not_observed",
            message: "The read side has not observed this merge snapshot",
            details: { merge_snapshot_id: }
          ),
          warnings: [ "The registration may exist while this projection is catching up." ],
          next_actions: []
        )
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "merge_snapshot_get input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "merge_snapshot_get input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
