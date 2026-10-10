# frozen_string_literal: true

RSpec.describe Coordinator::Read::Contracts::DevelopmentSearch do
  subject(:contract) { described_class.new }

  def literal(value = "checkpoint", match: "contains", **options)
    { match:, value:, **options }
  end

  def boolean(operator, *operands)
    { operator:, operands: }
  end

  def request(query, **options)
    { fields: [ { field: "skill.instructions", query: } ], **options }
  end

  it "accepts all literal operations and explicit Boolean case flags" do
    %w[contains starts_with ends_with equals].each do |match|
      expect(contract.call(request(literal(match:)))).to be_success
      expect(contract.call(request(literal(match:, case_sensitive: false)))).to be_success
    end
    expect(contract.call(JSON.parse(JSON.generate(request(literal))))).to be_success
  end

  it "accepts positive alternatives with nested exclusions and literal punctuation" do
    query = boolean("or", literal("foo"), boolean("and", literal("bar"), boolean("not", literal("===", match: "equals"))))
    expect(contract.call(request(query))).to be_success
    expect(contract.call(request(literal("foo%_\\bar\n")))).to be_success
    expect(contract.call(request(literal("日本語")))).to be_success
  end

  it "rejects every unanchored Boolean alternative rather than merely finding any positive term" do
    [
      literal("==="),
      boolean("not", literal),
      boolean("or", literal("foo"), boolean("not", literal("bar"))),
      boolean("or", literal("foo"), boolean("and", literal("==="), boolean("not", literal("bar")))),
      boolean("and", boolean("not", literal("foo")), boolean("not", literal("bar")))
    ].each { expect(contract.call(request(_1))).to be_failure }
  end

  it "handles nested negation in linear-size syntax without accepting a negative-only path" do
    query = boolean("and", literal("foo"), boolean("not", boolean("or", literal("bar"), literal("baz"))))
    expect(contract.call(request(query))).to be_success
    query = boolean("or", literal("foo"), boolean("not", boolean("and", literal("bar"), literal("baz"))))
    expect(contract.call(request(query))).to be_failure
  end

  it "counts Unicode characters rather than bytes and bounds literals" do
    [ "fo", "日本", "a" * 1025, "foo\0bar" ].each do |value|
      expect(contract.call(request(literal(value)))).to be_failure
    end
    expect(contract.call(request(literal("界" * 1024)))).to be_success
  end

  it "rejects unknown fields, operators, arbitrary regex and conflicting node shapes" do
    [
      literal.merge(sql: "DROP TABLE skills"),
      literal(match: "regex"),
      literal.merge(operator: "and", operands: [ literal, literal ]),
      { value: "foo" },
      boolean("xor", literal, literal),
      boolean("and", literal),
      boolean("not", literal, literal),
      boolean("and", literal, 42)
    ].each { expect(contract.call(request(_1))).to be_failure }
    expect(contract.call(request(literal).merge(fields: [ { field: "resource.content", query: literal } ]))).to be_failure
  end

  it "rejects coercion and unknown request/filter/field keys" do
    expect(contract.call(request(literal(case_sensitive: "false")))).to be_failure
    expect(contract.call(request(literal, limit: "10"))).to be_failure
    expect(contract.call(request(literal, combine: "and"))).to be_failure
    expect(contract.call(request(literal, history: true))).to be_failure
    expect(contract.call(request(literal, filters: { project: "home" }))).to be_failure
    expect(contract.call(request(literal).merge(fields: [ { field: "skill.name", query: literal, extra: true } ]))).to be_failure
  end

  it "bounds depth, width, nodes, field count and public pages before SQL compilation" do
    query = literal
    6.times { query = boolean("and", literal, query) }
    expect(contract.call(request(query))).to be_failure
    expect(contract.call(request(boolean("or", *Array.new(9) { literal })))).to be_failure
    query = boolean("or", *Array.new(8) { boolean("or", *Array.new(8) { literal }) })
    expect(contract.call(request(query))).to be_failure
    fields = Coordinator::Read::Search::FieldCatalog::SELECTORS.first(9).map { { field: _1, query: literal } }
    expect(contract.call(fields:)).to be_failure
    [ 0, 51 ].each { expect(contract.call(request(literal, limit: _1))).to be_failure }
    expect(contract.call(fields: [ request(literal)[:fields].first ] * 2)).to be_failure
  end

  it "allows only exact, independent filters and known corpus families" do
    expect(contract.call(request(literal, filters: {
      scope: "project:home", repository_id: SecureRandom.uuid_v7,
      entity_types: [ "skill", "development_artifact" ]
    }, limit: 50))).to be_success
    expect(contract.call(request(literal, filters: { repository_id: "home" }))).to be_failure
    expect(contract.call(request(literal, filters: { entity_types: [ "event" ] }))).to be_failure
  end

  it "bounds the entire UTF-8 request independently of per-literal and node limits" do
    query = boolean("and", *Array.new(8) { literal("界" * 1024) })
    fields = Coordinator::Read::Search::FieldCatalog::SELECTORS.first(4).map { { field: _1, query: } }
    expect(contract.call(fields:)).to be_failure
    expect(contract.call(fields:).errors.to_h.fetch(nil).join).to include("UTF-8 bytes")
  end

  it "accepts existing Repository scopes up to 500 UTF-8 bytes without accepting oversized or NUL text" do
    [ "project:" + "a" * 492, "project:" + "界" * 164 ].each do |scope|
      expect(contract.call(request(literal, filters: { scope: }))).to be_success
    end
    [ "a" * 501, "界" * 167, "foo\0bar", "project:latin".encode(Encoding::ISO_8859_1) ].each do |scope|
      expect(contract.call(request(literal, filters: { scope: }))).to be_failure
    end
  end
end
