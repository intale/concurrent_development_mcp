# frozen_string_literal: true

module Coordinator::Write
  module MergeAuthorizations
    class DependencyProgressV1 < Value
      attribute :dependency_id, Types::Identifier
      attribute :satisfaction_event, EventReference
      attribute :source_event, EventReference
    end
  end
end
