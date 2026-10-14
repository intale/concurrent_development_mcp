# frozen_string_literal: true

class AddModeledRelationNumbersToDevelopmentArtifacts < ActiveRecord::Migration[8.0]
  def change
    add_column :development_artifacts, :active_relations_number, :integer, null: false, default: 0
    add_column :development_artifacts, :lifetime_relations_number, :integer, null: false, default: 0
  end
end
