# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class NaturalKeyV1 < Value
      attribute :scope, Types::DevelopmentArtifactScope
      attribute :source, SourceV1
    end
  end
end
