# frozen_string_literal: true

RSpec.describe Coordinator::Read::Repositories::BatchWriter, :read_model do
  let(:model) { Coordinator::Read::Repository }
  let(:patches) { Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :repository_id ]) }
  let(:event_time) { Time.utc(2026, 10, 14, 12) }

  def persist
    described_class.new(model:, patches:).call
  end

  def writes
    statements = []
    capture = ->(_name, _start, _finish, _id, payload) { statements << payload.fetch(:sql) }
    ActiveSupport::Notifications.subscribed(capture, "sql.active_record") { yield }
    statements.grep(/\A(?:INSERT|UPDATE|DELETE)\b/i)
  end

  def creation_attributes(**attributes)
    attributes_for(:coordinator_read_repository, **attributes).merge(created_at: event_time, updated_at: event_time)
  end

  it "updates only introduced columns without an incomplete insert or replacing other fields" do
    row = create(:coordinator_read_repository, paths: [ "/keep" ], remotes: [ "https://keep.test/repo" ])
    original = row.attributes
    patches.assign(repository_id: row.repository_id, display_name: "changed", updated_at: event_time)

    sql = writes { persist }

    expect(sql.length).to eq(1)
    expect(sql.sole).to start_with("UPDATE")
    expect(row.reload.attributes.except("display_name", "updated_at")).to eq(original.except("display_name", "updated_at"))
    expect(row.display_name).to eq("changed")
    expect(row.updated_at).to eq(event_time)
  end

  it "clears an explicit null and safely serializes JSON, UTF-8 and SQL-like text" do
    row = create(:coordinator_read_repository)
    text = "α '); DELETE FROM repositories; --\n雪"
    patches.assign(repository_id: row.repository_id, display_name: nil, paths: [ text, "" ], updated_at: event_time)

    persist

    expect(row.reload.display_name).to be_nil
    expect(row.paths).to eq([ text, "" ])
    expect(model.count).to eq(1)
  end

  it "keeps separate column masks while combining compatible rows into one statement" do
    first, second, third = create_list(:coordinator_read_repository, 3)
    patches.assign(repository_id: first.repository_id, display_name: "first")
    patches.assign(repository_id: second.repository_id, display_name: "second")
    patches.assign(repository_id: third.repository_id, remotes: [ "https://third.test" ])

    expect(writes { persist }.length).to eq(2)
    expect(first.reload.display_name).to eq("first")
    expect(second.reload.display_name).to eq("second")
    expect(third.reload.remotes).to eq([ "https://third.test" ])
  end

  it "inserts complete rows before applying their final patches and converges on redelivery" do
    attributes = creation_attributes(paths: [])
    patches.insert(attributes)
    patches.assign(repository_id: attributes.fetch(:repository_id), display_name: "last", updated_at: event_time + 60)

    2.times { persist }

    row = model.find(attributes.fetch(:repository_id))
    expect(model.count).to eq(1)
    expect(row.display_name).to eq("last")
    expect(row.created_at).to eq(event_time)
    expect(row.updated_at).to eq(event_time + 60)
  end

  it "does not replace unrelated current columns when a creation is replayed" do
    row = create(:coordinator_read_repository, display_name: "current", paths: [ "/current" ])
    patches.insert(creation_attributes(repository_id: row.repository_id, display_name: nil, paths: []))

    persist

    expect(row.reload.display_name).to eq("current")
    expect(row.paths).to eq([ "/current" ])
  end

  it "rolls back the entire chunk if any later mask fails" do
    existing = create(:coordinator_read_repository, display_name: "before")
    added = creation_attributes
    patches.insert(added)
    patches.assign(repository_id: existing.repository_id, display_name: "after")
    patches.assign(repository_id: added.fetch(:repository_id), scope: nil)

    expect { persist }.to raise_error(ActiveRecord::NotNullViolation)

    expect(existing.reload.display_name).to eq("before")
    expect(model.where(repository_id: added.fetch(:repository_id))).not_to exist
  end

  it "applies content on rewind without using timestamps as an availability or replay gate" do
    row = create(:coordinator_read_repository, display_name: "before", updated_at: event_time + 120)
    patches.assign(repository_id: row.repository_id, display_name: "reapplied", updated_at: event_time)

    persist

    expect(row.reload.display_name).to eq("reapplied")
    expect(row.updated_at).to eq(event_time + 120)
  end

  it "reduces a thousand assignments to one database update" do
    row = create(:coordinator_read_repository)
    1000.times { |index| patches.assign(repository_id: row.repository_id, display_name: "name-#{index}") }

    expect(writes { persist }.length).to eq(1)
    expect(row.reload.display_name).to eq("name-999")
  end

  it "updates a thousand independent rows in one compatible statement" do
    rows = Array.new(1000) { creation_attributes }
    model.insert_all!(rows, record_timestamps: false)
    rows.each_with_index { |attributes, index| patches.assign(repository_id: attributes.fetch(:repository_id), display_name: "name-#{index}") }

    expect(writes { persist }.length).to eq(1)
    expect(model.where(display_name: "name-999").count).to eq(1)
    expect(model.count).to eq(1000)
  end

  it "does not write an empty or identity-only batch" do
    patches.assign(repository_id: SecureRandom.uuid_v7)

    expect(writes { persist }).to be_empty
  end
end
