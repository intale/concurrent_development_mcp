# frozen_string_literal: true

module Coordinator::Write
  class RequestedWorkIntentionV1 < Value
    attribute :prepared_target, Types.Instance(PreparedWorkIntentionTargetV1)
    attribute :resource, Types.Instance(WorkIntentionResourceV1)
  end
end
