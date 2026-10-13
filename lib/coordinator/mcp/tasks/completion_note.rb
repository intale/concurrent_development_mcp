# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    class CompletionNote
      READ_NOTE = "No read-back is needed to confirm this outcome. Read models may temporarily show older data; next-action reads are optional context, not persistence checks."

      def call(completion)
        explanation = case completion.outcome
        when "succeeded"
          if completion.scope == "request"
            "The request is durably recorded; downstream processing may continue. This confirms the requested intent, not downstream completion or rollback."
          elsif completion.effects == "unchanged"
            "The requested state was already satisfied; no new target changes were needed."
          else
            "The requested facts are durably committed. This does not imply that downstream Sagas or projections have finished."
          end
        when "partial_failure", "cancelled"
          case completion.effects
          when "partial", "committed"
            "The operation settled with retained effects. Earlier successful steps remain committed; they were not rolled back. Inspect the returned failed and unexecuted outcomes before deciding what to retry."
          when "unknown"
            "The operation stopped, but some effects are unresolved. Do not infer rollback or blindly repeat the entire operation."
          else
            "The operation settled without committed target effects. Inspect the unsuccessful or unexecuted outcomes before deciding what to retry."
          end
        else
          "The requested target changes did not commit. Correct the reported problem before a new intent; a retry may succeed when the error is retryable."
        end
        "#{explanation} #{READ_NOTE} Recover an unknown response by replaying the exact command_id and payload; a new corrective intent needs a new command_id."
      end
    end
  end
end
