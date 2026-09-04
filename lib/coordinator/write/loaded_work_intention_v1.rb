# frozen_string_literal: true

module Coordinator::Write
  class LoadedWorkIntentionV1 < Value
    attribute :state, Types.Instance(Domain::WorkIntentions::State)
    attribute :stream_revision, Types::Integer.constrained(gteq: 0).optional
  end
end
