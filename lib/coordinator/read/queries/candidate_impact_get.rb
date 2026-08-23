# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class CandidateImpactGet < Dry::Operation
      def initialize(
        contract: Contracts::CandidateImpactGet.new,
        impacts: Repositories::CandidateImpacts.new
      )
        @contract = contract
        @impacts = impacts
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = CandidateImpactGetQueryV1.new(
          candidate_id: validated[:candidate_id],
          direction: validated[:direction],
          after_global_position: validated[:after_global_position],
          limit: validated[:limit] || 20
        )
        page = @impacts.page(query)
        return not_found_result(query.candidate_id) unless page

        QueryResultV1.new(
          status: "ok",
          summary: "Latest available projected potential Candidate relationships; evidence is attributed and unverified.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::CandidateImpactData.new(page:),
          warnings: available_warnings(page),
          next_actions: available_next_actions(page)
        )
      end

      private

      def available_warnings(page)
        warnings = []
        unless page.candidate.manifest_observed
          warnings << "The Candidate manifest has not yet been observed by this projection."
        end
        if page.candidate.build_context_digest && !page.candidate.build_context_observed
          warnings << "The Candidate build context has not yet been observed by this projection."
        end
        unless page.impact_surface
          warnings << "The Candidate impact surface has not yet been observed by this projection."
        end
        case page.impact_policy&.enforcement
        when "advisory"
          warnings << "The latest available Candidate-impact policy is advisory; consider external verification."
        when "verification_gate", "merge_gate"
          warnings << "The latest available Candidate-impact policy is gating; the obligation projection may lag."
        end
        warnings.freeze
      end

      def available_next_actions(page)
        return [] unless %w[verification_gate merge_gate].include?(page.impact_policy&.enforcement)

        [
          NextAction.new(
            tool: "verification_obligations_list",
            arguments: NextAction::ChangeSetArguments.new(
              change_set_id: page.candidate.change_set_id
            )
          )
        ]
      end

      def not_found_result(candidate_id)
        QueryResultV1.new(
          status: "not_found",
          summary: "No projected Candidate submission is currently available for this Candidate ID.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "candidate_not_observed",
            message: "The read side has not observed this Candidate submission",
            details: { candidate_id: }
          ),
          warnings: [],
          next_actions: []
        )
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "candidate_impact_get input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "candidate_impact_get input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
