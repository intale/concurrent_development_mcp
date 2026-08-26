# frozen_string_literal: true

module Coordinator::Read
  class SkillRevision < ApplicationRecord
    belongs_to :skill,
               class_name: "Coordinator::Read::Skill",
               foreign_key: "skill_id",
               inverse_of: :revisions
  end
end
