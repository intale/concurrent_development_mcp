# frozen_string_literal: true

RSpec.describe Coordinator::Shared::Observability::McpOutcome do
  it "distinguishes accepted mutation handles, pending reads and terminal business outcomes" do
    cases = [
      [ { result: { resultType: "task", status: "working", taskId: "private" } }, "accepted" ],
      [ { result: { resultType: "complete", status: "working" } }, "pending" ],
      [ { result: { status: "cancelled" } }, "cancelled" ],
      [ { result: { status: "failed", statusMessage: "private" } }, "error" ],
      [ { result: { structuredContent: { status: "denied" } } }, "denied" ],
      [ { result: { status: "completed", result: { structuredContent: { status: "conflict" } } } }, "conflict" ],
      [ { result: { isError: true } }, "error" ],
      [ { result: { structuredContent: { status: "caller-controlled" } } }, "unknown" ],
      [ { result: {} }, "ok" ], [ nil, "ok" ]
    ]
    cases.each do |response, expected|
      expect(described_class.call(response)).to eq(expected)
      expect(described_class.call(JSON.generate(response))).to eq(expected)
    end
  end

  it "classifies protocol errors without retaining messages or arbitrary data" do
    expect(described_class.call(error: { code: -32_602, message: "private" })).to eq("invalid")
    expect(described_class.call(error: { code: -32_003 })).to eq("denied")
    expect(described_class.call(error: { code: -32_601 })).to eq("not_found")
    expect(described_class.call(error: { code: -32_603 })).to eq("error")
    expect(described_class.call(error: { code: -32_602, data: { code: "task_not_found" } })).to eq("not_found")
  end
end
