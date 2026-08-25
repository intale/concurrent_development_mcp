# frozen_string_literal: true

module Coordinator::Write
  class WorkItemOutputV1 < Value
    attribute :kind, Types::WorkItemOutputKind
    attribute :key, Types::Identifier
  end
end
