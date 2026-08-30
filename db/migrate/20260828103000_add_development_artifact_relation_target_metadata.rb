# frozen_string_literal: true

class AddDevelopmentArtifactRelationTargetMetadata < ActiveRecord::Migration[8.1]
  def change
    change_table :development_artifact_relations, bulk: true do |t|
      t.string :target_status, null: false
      t.string :target_name
      t.string :target_scope
    end
  end
end
