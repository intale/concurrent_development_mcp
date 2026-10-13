# frozen_string_literal: true

module Coordinator::Write::Events::ProjectionNumbers
  class SkillRevisionRepresentationRecordedV1 < Coordinator::Write::Events::Base
    contract type: "SkillRevisionRepresentationRecorded", version: 1

    attribute :skill_revision_id, Coordinator::Write::Types::UuidV7
  end
end
