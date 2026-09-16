# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DevelopmentArtifactTransitionV1 < Value
      attribute :state, DevelopmentArtifactSourceStateV1
      attribute :scope_changed, Types::Bool
      attribute :title_changed, Types::Bool
      attribute :kind_changed, Types::Bool
      attribute :source_changed, Types::Bool
      attribute :added_labels, Types::Array.of(Types::DevelopmentArtifactLabel)
      attribute :removed_labels, Types::Array.of(Types::DevelopmentArtifactLabel)
    end
  end
end
