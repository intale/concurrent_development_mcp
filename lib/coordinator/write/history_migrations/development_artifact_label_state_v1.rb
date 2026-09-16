# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DevelopmentArtifactLabelStateV1 < Value
      attribute :label, Types::DevelopmentArtifactLabel
      attribute :origin, DevelopmentArtifactPropertyOriginV1
    end
  end
end
