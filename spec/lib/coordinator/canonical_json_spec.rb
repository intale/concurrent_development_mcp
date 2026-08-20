# frozen_string_literal: true

RSpec.describe Coordinator::CanonicalJson do
  subject(:canonical_json) { described_class.new }

  describe "#encode" do
    it "recursively orders object keys while preserving array order" do
      value = {
        "z" => [ 3, 2, 1 ],
        "unicode" => "é",
        "a" => { "b" => 2, "a" => 1 }
      }

      expect(canonical_json.encode(value)).to eq(
        '{"a":{"a":1,"b":2},"unicode":"é","z":[3,2,1]}'
      )
      expect(canonical_json.sha256(value)).to eq(
        "sha256:ab4b6b0209f64c25ba8b17adde37d8a2b2edf8cc6ed85e74f1d3f05bbb1028af"
      )
    end

    it "freezes the command-input golden vector" do
      document = {
        command_id: "cmd-100",
        schema: "command-input/v1",
        tool_name: "change_set_create",
        input: {
          goal: "Update the shared API",
          change_set_id: "cs-100",
          actor: { actor_kind: "agent", actor_id: "agent-7" }
        }
      }

      expect(canonical_json.encode(document)).to eq(
        '{"command_id":"cmd-100","input":{"actor":{"actor_id":"agent-7","actor_kind":"agent"},' \
          '"change_set_id":"cs-100","goal":"Update the shared API"},' \
          '"schema":"command-input/v1","tool_name":"change_set_create"}'
      )
      expect(canonical_json.sha256(document)).to eq(
        "sha256:30740b1d13e52c66b555ac8324403844c759af42f8e8933ee7cb6a900f3b493a"
      )
    end

    it "is independent of hash insertion order" do
      pairs = [ [ "alpha", 1 ], [ "beta", { "y" => 2, "x" => 1 } ], [ "gamma", [ 3, 2, 1 ] ] ]
      expected = canonical_json.encode(pairs.to_h)
      random = Random.new(20_260_820)

      50.times do
        expect(canonical_json.encode(pairs.shuffle(random:).to_h)).to eq(expected)
      end
    end

    it "converts symbol keys and rejects collisions after key conversion" do
      expect(canonical_json.encode({ outer: { value: true } })).to eq('{"outer":{"value":true}}')

      expect { canonical_json.encode({ "same" => 1, same: 2 }) }
        .to raise_error(described_class::DuplicateKey, /same/)
    end

    it "preserves Unicode sequences rather than normalizing them" do
      composed = "é"
      decomposed = "e\u0301"

      expect(canonical_json.encode({ value: composed })).not_to eq(
        canonical_json.encode({ value: decomposed })
      )
    end

    it "accepts the cross-language safe integer boundaries" do
      expect(canonical_json.encode([ described_class::MIN_SAFE_INTEGER, described_class::MAX_SAFE_INTEGER ])).to eq(
        "[-9007199254740991,9007199254740991]"
      )
    end

    it "rejects integers outside the cross-language safe range" do
      expect { canonical_json.encode(described_class::MAX_SAFE_INTEGER + 1) }
        .to raise_error(described_class::UnsafeInteger)
      expect { canonical_json.encode(described_class::MIN_SAFE_INTEGER - 1) }
        .to raise_error(described_class::UnsafeInteger)
    end

    it "rejects floats and arbitrary Ruby objects" do
      expect { canonical_json.encode(1.25) }.to raise_error(described_class::UnsupportedValue, /Float/)
      expect { canonical_json.encode(Time.utc(2026, 8, 20)) }
        .to raise_error(described_class::UnsupportedValue, /Time/)
    end

    it "rejects invalid or non-UTF-8 strings" do
      invalid_utf8 = [ 0xff ].pack("C").force_encoding(Encoding::UTF_8)
      latin1 = "é".encode(Encoding::ISO_8859_1)

      expect { canonical_json.encode(invalid_utf8) }.to raise_error(described_class::InvalidString)
      expect { canonical_json.encode(latin1) }.to raise_error(described_class::InvalidString)
    end

    it "rejects cyclic and excessively nested values" do
      cyclic = []
      cyclic << cyclic
      nested = nil
      (described_class::MAX_NESTING + 1).times { nested = [ nested ] }

      expect { canonical_json.encode(cyclic) }.to raise_error(described_class::CycleDetected)
      expect { canonical_json.encode(nested) }.to raise_error(described_class::NestingExceeded)
    end
  end
end
