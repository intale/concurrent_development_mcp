# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkItemCompetitiveModeSelectedV1 < Base
      contract type: "WorkItemCompetitiveModeSelected", version: 1

      attribute :work_item_id, Types::Identifier
      attribute :competitive_mode, Types::Strict::Bool
    end
  end
end
