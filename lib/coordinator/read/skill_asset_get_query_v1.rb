# frozen_string_literal: true

module Coordinator::Read
  class SkillAssetGetQueryV1 < Value
    attribute :name, Types::SkillName
    attribute :scope, Types::SkillScope
    attribute :path, Types::SkillAssetPath
    attribute :revision, Types::SkillRevision.optional
  end
end
