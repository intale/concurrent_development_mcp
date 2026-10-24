# frozen_string_literal: true

module Coordinator::Mcp::UsageSkills
  class GetContract < Dry::Validation::Contract
    config.validate_keys = true

    params do
      required(:name).filled(:string)
      required(:scope).filled(:string)
      optional(:revision).maybe(:integer, gteq?: 1)
    end
  end
end
