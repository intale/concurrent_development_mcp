# frozen_string_literal: true

RSpec.describe Coordinator::Write::Content::Builder do
  subject(:builder) { described_class.new }

  it "keeps valid UTF-8 as text and derives integrity evidence from exact bytes" do
    content = builder.call(
      encoding: "utf-8",
      media_type: "text/plain",
      text: "héllo\n"
    ).value!

    expect(content.to_h).to eq(
      encoding: "utf-8",
      media_type: "text/plain",
      text: "héllo\n",
      content_sha256: "sha256:b95becd154aa095f76c4ca47a5aeb8350d6dfcb838404edfc9dae06628de938d",
      byte_size: 7
    )
    expect(content.to_h).not_to have_key(:base64)
  end

  it "keeps explicitly tagged binary canonical and derives evidence after server decoding" do
    content = builder.call(
      encoding: "binary",
      media_type: "application/octet-stream",
      base64: "AP8K"
    ).value!

    expect(content.to_h).to eq(
      encoding: "binary",
      media_type: "application/octet-stream",
      base64: "AP8K",
      content_sha256: "sha256:712450d3c4a79eea9509e75dc1dacdeff58034df538536cfae2da882bd8a0c50",
      byte_size: 3
    )
    expect(content.to_h).not_to have_key(:text)
  end

  it "rejects mixed, malformed, invalidly encoded, oversized, and unknown input fields" do
    invalid = [
      { encoding: "utf-8", media_type: "text/plain", text: "ok", base64: "b2s=" },
      { encoding: "binary", media_type: "application/octet-stream", base64: "AA==\n" },
      { encoding: "utf-8", media_type: "text/plain", text: "\xFF".b.force_encoding(Encoding::UTF_8) },
      { encoding: "utf-8", media_type: "text/plain", text: "a" * (Coordinator::Shared::Types::CONTENT_MAXIMUM_BYTES + 1) },
      { encoding: "utf-8", media_type: "text/plain", text: "ok", digest: "caller-owned" }
    ]

    invalid.each do |input|
      failure = builder.call(input).failure

      expect(failure.code).to eq(:content_invalid)
      expect(failure.details.fetch(:errors)).not_to be_empty
    end
  end
end
