# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshots
    class ProducerV1 < Value
      attribute :name, Types::MergeSnapshotProducerName
      attribute :version, Types::MergeSnapshotProducerVersion
    end
  end
end
