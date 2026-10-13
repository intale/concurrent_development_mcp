# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projections::Batches::ColumnPatches do
  subject(:patches) { described_class.new(identity_columns: [ :entity_id ]) }

  it "coalesces assignments in delivered order without inventing absent columns" do
    patches.assign(entity_id: "entity", foo: "first")
    patches.assign(entity_id: "entity", bar: "second")
    patches.assign(entity_id: "entity", foo: "last")

    group = patches.update_groups.fetch(0)
    expect(group.columns).to eq([ :bar, :foo ])
    expect(group.rows).to eq([ { entity_id: "entity", foo: "last", bar: "second" } ])
  end

  it "retains explicit null as a change rather than an absent value" do
    patches.assign(entity_id: "entity", foo: "first")
    patches.assign(entity_id: "entity", foo: nil)

    expect(patches.update_groups.fetch(0).rows).to eq([ { entity_id: "entity", foo: nil } ])
  end

  it "groups compatible column masks without null-padding other rows" do
    patches.assign(entity_id: "first", foo: "one")
    patches.assign(entity_id: "second", foo: "two")
    patches.assign(entity_id: "third", bar: "three")

    groups = patches.update_groups.to_h { [ _1.columns, _1.rows ] }
    expect(groups.fetch([ :foo ])).to eq([
      { entity_id: "first", foo: "one" }, { entity_id: "second", foo: "two" }
    ])
    expect(groups.fetch([ :bar ])).to eq([ { entity_id: "third", bar: "three" } ])
  end

  it "keeps insert-if-absent defaults separate from subsequent updates" do
    patches.insert(entity_id: "entity", foo: "initial", bar: "default")
    patches.assign(entity_id: "entity", foo: "changed")

    expect(patches.inserts).to eq([ { entity_id: "entity", foo: "initial", bar: "default" } ])
    expect(patches.update_groups.fetch(0).rows).to eq([ { entity_id: "entity", foo: "changed" } ])
  end

  it "does not duplicate a stable creation or lose assignments on redelivery" do
    2.times do
      patches.insert(entity_id: "entity", foo: "initial")
      patches.assign(entity_id: "entity", bar: "changed")
    end

    expect(patches.inserts).to eq([ { entity_id: "entity", foo: "initial" } ])
    expect(patches.update_groups.fetch(0).rows).to eq([ { entity_id: "entity", bar: "changed" } ])
  end

  it "does not carry changes from another delivered batch" do
    patches.assign(entity_id: "entity", foo: "previous batch")
    next_batch = described_class.new(identity_columns: [ :entity_id ])
    next_batch.assign(entity_id: "entity", bar: "current batch")

    expect(next_batch.update_groups.fetch(0).rows).to eq([
      { entity_id: "entity", bar: "current batch" }
    ])
  end

  it "preserves JSON, text, false and timestamp values without converting or validating them" do
    timestamp = Time.utc(2026, 10, 13, 12)
    attributes = { entity_id: "entity", body: "UTF-8 α\n'", enabled: false,
                   payload: { "items" => [ 1, nil, "text" ] }, updated_at: timestamp }
    patches.assign(attributes)

    expect(patches.update_groups.fetch(0).rows).to eq([ attributes ])
  end

  it "supports compound identities without digest keys or separator collisions" do
    patches = described_class.new(identity_columns: [ :owner_id, :member_id ])
    patches.assign(owner_id: "a:b", member_id: "c", value: "first")
    patches.assign(owner_id: "a", member_id: "b:c", value: "second")

    expect(patches.update_groups.fetch(0).rows.length).to eq(2)
  end

  it "does not retain a caller's mutable attribute hash" do
    attributes = { entity_id: "entity", foo: "before" }
    patches.assign(attributes)
    attributes[:foo] = "after"

    expect(patches.update_groups.fetch(0).rows.first.fetch(:foo)).to eq("before")
  end

  it "does not issue an update for identity-only input" do
    patches.assign(entity_id: "entity")

    expect(patches.update_groups).to be_empty
    expect(patches).to be_empty
  end
end
