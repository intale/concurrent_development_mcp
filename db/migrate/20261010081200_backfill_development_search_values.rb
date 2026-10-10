# frozen_string_literal: true

class BackfillDevelopmentSearchValues < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Triggers/indexes are already committed. Each batch locks only current
    # source rows and commits independently, allowing concurrent projection.
    Coordinator::Read::Repositories::SearchValueBackfill.new.call
  end

  def down
    # Derived data remains valid for the already-installed schema and triggers.
  end
end
