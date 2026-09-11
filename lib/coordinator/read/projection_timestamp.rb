# frozen_string_literal: true

module Coordinator::Read
  class ProjectionTimestamp
    def call(current:, event:)
      observed = event.created_at.utc
      current && current > observed ? current : observed
    end
  end
end
