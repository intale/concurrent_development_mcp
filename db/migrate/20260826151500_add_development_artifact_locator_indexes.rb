# frozen_string_literal: true

class AddDevelopmentArtifactLocatorIndexes < ActiveRecord::Migration[8.1]
  def change
    add_column :development_artifacts, :observed_sequence, :bigserial, null: false
    add_index :development_artifacts, :observed_sequence, unique: true
    add_index :development_artifacts,
              :source_locator,
              using: :hash,
              name: "index_development_artifacts_on_source_locator_hash"
    add_index :development_artifacts,
              %i[scope source_kind source_revision observed_sequence],
              name: "index_development_artifacts_on_exact_locator_context"
  end
end
