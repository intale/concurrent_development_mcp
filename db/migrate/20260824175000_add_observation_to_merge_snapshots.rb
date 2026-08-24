# frozen_string_literal: true

class AddObservationToMergeSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :merge_snapshots, :observation, :jsonb
  end
end
