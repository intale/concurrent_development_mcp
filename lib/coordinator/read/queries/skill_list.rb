# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class SkillList < Dry::Operation
      def initialize(contract: Contracts::SkillList.new, skills: Repositories::Skills.new)
        @contract = contract
        @skills = skills
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = SkillListQueryV1.new(
          name: validated[:name],
          scope: validated[:scope],
          after_updated_at: nil,
          after_skill_id: validated[:after_skill_id],
          limit: validated[:limit] || 20
        )
        QueryResultV1.new(
          status: "ok",
          summary: "Latest available projected Skills in deterministic Skill-ID order.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::SkillPageData.new(page: @skills.page(query)),
          warnings: [],
          next_actions: []
        )
      end

      private

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "skill_list input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "skill_list input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
