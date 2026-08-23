# frozen_string_literal: true

class CreateVerificationObligations < ActiveRecord::Migration[8.1]
  def change
    create_table :verification_obligations, id: false do |table|
      table.string :obligation_id, null: false, primary_key: true
      table.string :kind, null: false
      table.string :status, null: false
      table.string :change_set_id, null: false
      table.string :source_candidate_id, null: false
      table.string :target_candidate_id, null: false
      table.string :source_work_item_id, null: false
      table.string :target_work_item_id, null: false
      table.string :source_repository_id, null: false
      table.string :target_repository_id, null: false
      table.string :enforcement, null: false
      table.jsonb :obligation, null: false
      table.jsonb :event, null: false
      table.jsonb :actor, null: false
      table.jsonb :markers, null: false, default: []
      table.jsonb :metadata, null: false, default: {}
      table.string :causation_id
      table.string :correlation_id
      table.bigint :event_global_position, null: false
      table.datetime :created_at_domain, null: false, precision: 6
      table.datetime :created_at_store, null: false, precision: 6
      table.timestamps null: false, precision: 6
    end

    add_index :verification_obligations,
              %i[change_set_id status event_global_position],
              name: "idx_verification_obligations_change_set"
    add_index :verification_obligations,
              %i[source_candidate_id event_global_position],
              name: "idx_verification_obligations_source_candidate"
    add_index :verification_obligations,
              %i[target_candidate_id event_global_position],
              name: "idx_verification_obligations_target_candidate"
    add_index :verification_obligations,
              %i[source_work_item_id event_global_position],
              name: "idx_verification_obligations_source_work_item"
    add_index :verification_obligations,
              %i[target_work_item_id event_global_position],
              name: "idx_verification_obligations_target_work_item"
    add_index :verification_obligations,
              %i[source_repository_id event_global_position],
              name: "idx_verification_obligations_source_repository"
    add_index :verification_obligations,
              %i[target_repository_id event_global_position],
              name: "idx_verification_obligations_target_repository"
    add_index :verification_obligations,
              %i[kind event_global_position],
              name: "idx_verification_obligations_kind"
    add_index :verification_obligations,
              %i[enforcement event_global_position],
              name: "idx_verification_obligations_enforcement"
    add_index :verification_obligations,
              %i[status event_global_position],
              name: "idx_verification_obligations_status"
    add_index :verification_obligations,
              :event_global_position,
              name: "idx_verification_obligations_position"
  end
end
