# frozen_string_literal: true

module Coordinator::Mcp::UsageSkills
  class AssetContract < GetContract
    params do
      required(:path).filled(:string)
    end
  end
end
