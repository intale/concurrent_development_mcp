# frozen_string_literal: true

module Coordinator::Write::Events::ProjectionNumbers
  class DevelopmentArtifactRelationsReconciliationFailedV1 < Coordinator::Write::Events::Base
    contract type: "DevelopmentArtifactRelationsReconciliationFailed", version: 1

    attribute :statistics_id, Coordinator::Write::Types::UuidV7
    attribute :source_event_id, Coordinator::Write::Types::UuidV7
    attribute :failure, Coordinator::Write::Tasks::ExecutionFailureV1
  end
end
