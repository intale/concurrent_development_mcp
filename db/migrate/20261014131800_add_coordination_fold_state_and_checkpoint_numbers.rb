# frozen_string_literal: true

class AddCoordinationFoldStateAndCheckpointNumbers < ActiveRecord::Migration[8.0]
  def change
    add_column :coordinator_contexts, :repository_checkpoint_numbers, :jsonb, null: false, default: {}
    add_column :attempt_histories, :work_intention_member_states, :jsonb, null: false, default: {}
  end
end
