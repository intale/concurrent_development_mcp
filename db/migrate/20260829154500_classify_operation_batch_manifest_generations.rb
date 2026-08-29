# frozen_string_literal: true

class ClassifyOperationBatchManifestGenerations < ActiveRecord::Migration[8.1]
  def up
    add_column :operation_batches, :manifest_generation, :string
    add_check_constraint :operation_batches,
                         "manifest_generation IN ('pre_semantic', 'semantic')",
                         name: "operation_batches_manifest_generation"
    execute <<~SQL.squish
      UPDATE operation_batches
      SET manifest_generation = 'pre_semantic'
      WHERE manifest_generation IS NULL
    SQL
  end

  def down
    remove_check_constraint :operation_batches, name: "operation_batches_manifest_generation"
    remove_column :operation_batches, :manifest_generation
  end
end
