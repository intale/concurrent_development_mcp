# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class CompletionFactV1 < Value
      attribute :payload, Events::ReleaseSetCompletedV1
      attribute :event, EventReference
    end
  end
end
