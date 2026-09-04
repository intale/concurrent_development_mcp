# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkItemOutputRecordedV1 < Base
      contract type: "WorkItemOutputRecorded", version: 1

      attribute :work_item_id, Types::Identifier
      attribute :output_kind, Types::WorkItemOutputKind
      attribute :output_key, Types::Identifier
    end
  end
end
