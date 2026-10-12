class CreateWorkIntentionRenewals < ActiveRecord::Migration[8.1]
  def change
    create_table :coordinator_work_intention_renewals do |t|
      t.uuid :renewal_id, null: false
      t.uuid :task_id
      t.uuid :intention_set_id
      t.string :attempt_id
      t.string :actor_kind
      t.string :actor_id
      t.string :status, null: false, default: "requested"
      t.datetime :expires_at
      t.jsonb :members, null: false, default: []
      t.jsonb :failure
      t.jsonb :request_event
      t.jsonb :terminal_event
      t.uuid :correlation_id
      t.timestamps
    end
    add_index :coordinator_work_intention_renewals, :renewal_id, unique: true
    add_index :coordinator_work_intention_renewals, :task_id, unique: true
    add_index :coordinator_work_intention_renewals, [ :intention_set_id, :updated_at, :renewal_id ]
  end
end
