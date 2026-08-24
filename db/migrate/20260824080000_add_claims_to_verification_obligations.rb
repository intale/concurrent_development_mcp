# frozen_string_literal: true

class AddClaimsToVerificationObligations < ActiveRecord::Migration[8.1]
  def change
    change_table :verification_obligations, bulk: true do |table|
      table.jsonb :claim
      table.string :claim_id
      table.string :claimant_id
      table.integer :claim_fencing_token
      table.datetime :claim_claimed_at_domain, precision: 6
      table.datetime :claim_expires_at_domain, precision: 6
      table.jsonb :claim_event
      table.jsonb :claim_actor
      table.jsonb :claim_markers
      table.jsonb :claim_metadata
      table.string :claim_causation_id
      table.string :claim_correlation_id
      table.bigint :claim_event_global_position
      table.integer :claim_stream_revision
      table.datetime :claim_created_at_store, precision: 6
    end

    add_index :verification_obligations,
              %i[claimant_id event_global_position],
              name: "idx_verification_obligations_claimant"
    add_index :verification_obligations,
              %i[claim_expires_at_domain event_global_position],
              name: "idx_verification_obligations_claim_expiry"
  end
end
