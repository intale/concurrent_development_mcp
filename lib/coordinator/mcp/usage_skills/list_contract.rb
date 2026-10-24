# frozen_string_literal: true

module Coordinator::Mcp::UsageSkills
  class ListContract < Dry::Validation::Contract
    config.validate_keys = true

    params do
      optional(:source).maybe(:string, included_in?: [ "server" ])
      optional(:name).maybe(:string)
      optional(:scope).maybe(:string, included_in?: [ Catalog::SCOPE ])
      optional(:after_skill_id).maybe(:string)
      optional(:limit).maybe(:integer, gteq?: 1, lteq?: 100)
    end

    rule(:after_skill_id) do
      if value && Catalog.all.none? { _1.name == value }
        key.failure("must identify a built-in server Skill")
      end
    end
  end
end
