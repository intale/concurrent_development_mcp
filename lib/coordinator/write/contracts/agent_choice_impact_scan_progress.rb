# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AgentChoiceImpactScanProgress < Dry::Validation::Contract
      params do
        required(:command).value(Types.Instance(Commands::ProgressAgentChoiceImpactScan))
      end

      rule(:command) do
        count = value.page_choice_count
        last = value.last_processed_position

        key.failure("empty pages cannot have a last position") if count.zero? && last
        key.failure("non-empty pages require a last position") if count.positive? && !last
        key.failure("a sentinel requires one full page") if value.has_more && count != 50
        if last && last < value.previous_from_position
          key.failure("last position cannot precede the page cursor")
        end
      end
    end
  end
end
