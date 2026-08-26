# frozen_string_literal: true

module Coordinator::Read
  class Skill < ApplicationRecord
    self.primary_key = "skill_id"

    has_many :assets,
             class_name: "Coordinator::Read::SkillAsset",
             foreign_key: "skill_id",
             inverse_of: :skill,
             dependent: :delete_all

    has_many :revisions,
             class_name: "Coordinator::Read::SkillRevision",
             foreign_key: "skill_id",
             inverse_of: :skill,
             dependent: :delete_all
  end
end
