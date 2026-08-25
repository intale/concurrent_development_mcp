# frozen_string_literal: true

module Coordinator::Write
  class RequiredOutput < Value
    attribute :kind, Types::DependencyRequiredOutputKind
    attribute :key, Types::Identifier
  end
end
