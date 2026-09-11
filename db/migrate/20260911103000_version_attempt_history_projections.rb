# frozen_string_literal: true

class VersionAttemptHistoryProjections < ActiveRecord::Migration[8.1]
  def change
    add_column :attempt_histories, :projection_version, :integer, null: false, default: 4
  end
end
