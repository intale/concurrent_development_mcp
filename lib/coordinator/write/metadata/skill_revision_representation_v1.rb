# frozen_string_literal: true

module Coordinator::Write::Metadata
  class SkillRevisionRepresentationV1 < Coordinator::Write::EventMetadata
    attribute :asset_count, Coordinator::Write::Types::Integer.constrained(
      gteq: 0, lteq: Coordinator::Write::Types::SKILL_ASSET_MAXIMUM_COUNT
    )
  end
end
