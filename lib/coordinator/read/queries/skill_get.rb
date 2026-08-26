# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class SkillGet < Dry::Operation
      def initialize(contract: Contracts::SkillGet.new, skills: Repositories::Skills.new)
        @contract = contract
        @skills = skills
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = SkillGetQueryV1.new(
          name: validated[:name],
          scope: validated[:scope],
          revision: validated[:revision]
        )
        skill = @skills.fetch(name: query.name, scope: query.scope, revision: query.revision)
        return not_found_result(query) unless skill

        QueryResultV1.new(
          status: "ok",
          summary: query.revision ?
            "Requested projected Skill revision for the exact name and scope." :
            "Latest available projected revision for the exact Skill name and scope.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::SkillData.new(skill:),
          warnings: [],
          next_actions: []
        )
      end

      private

      def not_found_result(query)
        QueryResultV1.new(
          status: "not_found",
          summary: "No projected Skill is currently available for this exact name and scope.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "skill_not_observed",
            message: "The read side has not observed this Skill",
            details: { name: query.name, scope: query.scope, revision: query.revision }.compact
          ),
          warnings: [],
          next_actions: []
        )
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "skill_get input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "skill_get input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
