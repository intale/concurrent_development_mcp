# frozen_string_literal: true

RSpec.describe Coordinator::Shared::Markers::CodecV2 do
  subject(:codec) { described_class.new }

  def encode(**components)
    codec.call(
      purpose: "skill-natural-key",
      components: components.map { |dimension, value| { dimension: dimension.to_s, value: } }
    )
  end

  it "uses canonical readable byte-length framing independent of component order" do
    first = codec.call(
      purpose: "skill-natural-key",
      components: [
        { dimension: "scope", value: "home" },
        { dimension: "name", value: "a:b" }
      ]
    ).value!
    second = encode(name: "a:b", scope: "home").value!

    expect(first).to eq(second)
    expect(first.marker).to eq(
      "compound:skill-natural-key:v2|8:name=a:b|10:scope=home"
    )
    expect(first.marker).not_to match(/sha|md5/i)
  end

  it "keeps separators, empty values, and prefix-like content collision-safe and decodable" do
    first = encode(name: "a:b|7:scope=x", scope: "").value!
    second = encode(name: "a", scope: "b|7:scope=x").value!

    expect(first.marker).not_to eq(second.marker)
    expect(codec.decode(first.marker).value!).to eq(first)
    expect(codec.decode(second.marker).value!).to eq(second)
    expect(first.definition.components.find { _1.dimension == "scope" }.value).to eq("")
  end

  it "normalizes canonically equivalent Unicode before selecting an identity" do
    composed = encode(name: "caf\u00E9", scope: "home").value!
    decomposed = encode(name: "cafe\u0301", scope: "home").value!

    expect(decomposed).to eq(composed)
    expect(codec.decode(composed.marker).value!.definition.components.first.value).to eq("caf\u00E9")
  end

  it "rejects ambiguous definitions through the dry validation contract" do
    invalid_definitions = [
      { purpose: "Not-Lowercase", components: [ { dimension: "name", value: "skill" } ] },
      {
        purpose: "skill-natural-key",
        components: [ { dimension: "name", value: "one" }, { dimension: "name", value: "two" } ]
      },
      { purpose: "skill-natural-key", components: [ { dimension: "name", value: " padded" } ] },
      { purpose: "skill-natural-key", components: [ { dimension: "name", value: "line\nbreak" } ] },
      { purpose: "skill-natural-key", components: [ { dimension: "name", value: "compound:other:v2|1:x" } ] }
    ]

    invalid_definitions.each do |definition|
      failure = codec.call(**definition).failure

      expect(failure.code).to eq(:invalid_selector)
      expect(failure.errors).not_to be_empty
    end
  end

  it "rejects oversized selectors without shortening them to a digest" do
    failure = encode(name: "a" * Coordinator::Shared::Types::COMPOUND_MARKER_MAXIMUM_BYTES).failure

    expect(failure.code).to eq(:selector_too_large)
    expect(failure.message).to include("byte limit")
  end

  it "rejects truncated and noncanonical encoded input" do
    malformed = [
      "compound:skill-natural-key:v2|9:name=short",
      "compound:skill-natural-key:v2|08:name=a:b",
      "compound:skill-natural-key:v2|8:name=a:b|10:scope=home|",
      "compound:skill-natural-key:v1|8:name=a:b"
    ]

    malformed.each do |marker|
      expect(codec.decode(marker).failure.code).to eq(:invalid_selector)
    end
  end
end
