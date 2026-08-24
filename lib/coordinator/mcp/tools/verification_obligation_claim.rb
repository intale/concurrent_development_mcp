# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class VerificationObligationClaim < MutationTool
        tool_name "verification_obligation_claim"
        title "Claim a verification obligation"
        description "Acquire one temporary exclusive fenced claim over an exact open verification obligation. The claim coordinates external work; it does not start or verify that work."
        input_schema Schemas.verification_obligation_claim
        operation "operations.submit_claim_verification_obligation_task"
      end
    end
  end
end
