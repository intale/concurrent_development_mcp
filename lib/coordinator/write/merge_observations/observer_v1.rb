# frozen_string_literal: true

module Coordinator::Write
  module MergeObservations
    class ObserverV1 < Value
      attribute :name, Types::MergeSnapshotProducerName
      attribute :version, Types::MergeSnapshotProducerVersion
    end
  end
end
