# frozen_string_literal: true

module Coordinator::Read
  class SkillAsset < ApplicationRecord
    belongs_to :skill,
               class_name: "Coordinator::Read::Skill",
               foreign_key: "skill_id",
               inverse_of: :assets
  end
end
