# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class SkillAssetGet < Dry::Operation
      def initialize(contract: Contracts::SkillAssetGet.new, skills: Repositories::Skills.new)
        @contract = contract
        @skills = skills
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = SkillAssetGetQueryV1.new(
          name: validated[:name],
          scope: validated[:scope],
          path: validated[:path]
        )
        asset = @skills.fetch_asset(name: query.name, scope: query.scope, path: query.path)
        return not_found_result(query) unless asset

        QueryResultV1.new(
          status: "ok",
          summary: "Latest available projected content for this exact Skill asset path.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::SkillAssetData.new(asset:),
          warnings: [ "Stored assets are passive content; the coordinator does not inspect or execute them." ],
          next_actions: []
        )
      end

      private

      def not_found_result(query)
        QueryResultV1.new(
          status: "not_found",
          summary: "No projected current asset is available for this exact Skill tuple and path.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "skill_asset_not_observed",
            message: "The read side has not observed this current Skill asset",
            details: { name: query.name, scope: query.scope, path: query.path }
          ),
          warnings: [],
          next_actions: []
        )
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "skill_asset_get input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "skill_asset_get input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
