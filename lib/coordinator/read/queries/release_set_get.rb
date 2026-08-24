# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class ReleaseSetGet < Dry::Operation
      def initialize(contract: Contracts::ReleaseSetGet.new, release_sets: Repositories::ReleaseSets.new)
        @contract = contract
        @release_sets = release_sets
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = ReleaseSetGetQueryV1.new(release_set_id: validated[:release_set_id])
        release_set = @release_sets.fetch(query.release_set_id)
        return not_found_result(query.release_set_id) unless release_set

        QueryResultV1.new(
          status: "ok",
          summary: "Latest available ReleaseSet projection.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::ReleaseSetData.new(release_set:),
          warnings: [ "This view may lag the authoritative event store." ],
          next_actions: []
        )
      end

      private

      def not_found_result(release_set_id)
        QueryResultV1.new(
          status: "not_found",
          summary: "No projected ReleaseSet is currently available for this ID.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "release_set_not_observed",
            message: "The read side has not observed this ReleaseSet",
            details: { release_set_id: }
          ),
          warnings: [ "The ReleaseSet may exist while this projection is catching up." ],
          next_actions: []
        )
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "release_set_get input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "release_set_get input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
