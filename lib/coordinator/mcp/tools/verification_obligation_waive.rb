# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class VerificationObligationWaive < MutationTool
        tool_name "verification_obligation_waive"
        title "Waive a verification obligation"
        description "Record an exact user-attributed waiver for a current open or failed verification obligation. A waiver is a coordination override, not proof that verification passed."
        input_schema Schemas.verification_obligation_waive
        operation "operations.submit_waive_verification_obligation_task"
      end
    end
  end
end
