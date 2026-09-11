# frozen_string_literal: true

class RemoveMessageRevisionUniquenessFromDecisionInterpretations < ActiveRecord::Migration[8.0]
  def change
    remove_index :decision_interpretations, column: %i[message_id stream_revision]
    add_index :decision_interpretations,
              %i[message_id updated_at interpretation_id],
              order: { updated_at: :desc, interpretation_id: :desc },
              name: "idx_decision_interpretations_message_event_time"
  end
end
