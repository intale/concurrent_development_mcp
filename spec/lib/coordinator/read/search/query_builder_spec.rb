# frozen_string_literal: true

RSpec.describe Coordinator::Read::Search::QueryBuilder do
  let(:codec) { Coordinator::Read::Search::CursorCodec.new(secret: "search-test-cursor-integrity") }
  subject(:builder) { described_class.new(cursor_codec: codec) }

  def input(value: "checkpoint", **options)
    { fields: [ { field: "skill.instructions", query: { match: "contains", value: } } ], **options }
  end

  it "normalizes defaults into typed expressions and allows a page-size change with the same cursor" do
    query = builder.call(input).value!
    expect(query.limit).to eq(20)
    expect(query.fields.first.expression.case_sensitive).to be(true)
    boundary = Coordinator::Read::Search::CursorBoundary.new(updated_at: "2026-10-10T08:00:00.000000Z", entity_type: "skill", document_id: SecureRandom.uuid_v7)
    cursor = codec.encode(boundary:, fingerprint: query.fingerprint)
    resumed = builder.call(input(cursor:, limit: 1)).value!
    expect(resumed.boundary).to eq(boundary)
    expect(resumed.limit).to eq(1)
  end

  it "binds cursors to matching fields, literals, cases and filters, not JSON key order" do
    query = builder.call(input(filters: { scope: "project:home" })).value!
    boundary = Coordinator::Read::Search::CursorBoundary.new(updated_at: "2026-10-10T08:00:00.000000Z", entity_type: "skill", document_id: SecureRandom.uuid_v7)
    cursor = codec.encode(boundary:, fingerprint: query.fingerprint)
    expect(builder.call(input(cursor:, filters: { scope: "project:home" }))).to be_success
    expect(builder.call(JSON.parse(JSON.generate(input(cursor:, filters: { scope: "project:home" }))))).to be_success
    expect(builder.call(input(cursor:, value: "different", filters: { scope: "project:home" }))).to be_failure
    expect(builder.call(input(cursor:, filters: { scope: "project:work" }))).to be_failure
  end

  it "rejects cursor tampering, trailing segments and malformed opaque values" do
    query = builder.call(input).value!
    boundary = Coordinator::Read::Search::CursorBoundary.new(updated_at: "2026-10-10T08:00:00.000000Z", entity_type: "skill", document_id: SecureRandom.uuid_v7)
    cursor = codec.encode(boundary:, fingerprint: query.fingerprint)
    [ "bad-cursor", "#{cursor}.extra", cursor.sub(/.$/, cursor[-1] == "0" ? "1" : "0") ].each do |invalid|
      expect(builder.call(input(cursor: invalid)).failure.code).to eq("invalid_cursor")
    end
  end

  it "fails semantic validation before constructing any query" do
    expect(builder.call(input(value: "xy")).failure.code).to eq("invalid_input")
    expect(builder.call(input(filters: { scope: "project:\0home" })).failure.code).to eq("invalid_input")
  end
end
