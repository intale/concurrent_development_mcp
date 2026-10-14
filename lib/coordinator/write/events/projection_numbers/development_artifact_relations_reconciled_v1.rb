# frozen_string_literal: true

module Coordinator::Write::Events::ProjectionNumbers
  class DevelopmentArtifactRelationsReconciledV1 < Coordinator::Write::Events::Base
    contract type: "DevelopmentArtifactRelationsReconciled", version: 1

    attribute :statistics_id, Coordinator::Write::Types::UuidV7
    attribute :source_event_id, Coordinator::Write::Types::UuidV7
  end
end
