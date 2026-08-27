# frozen_string_literal: true

RSpec.describe Coordinator::Processes::InternalCommandIdBuilder do
  it "builds one deterministic reserved command identity through the shared type" do
    identity = "batch:outcome:0198c000-0000-7000-8000-000000000001:0"

    command_id = described_class.call(identity)

    expect(command_id).to eq("internal:#{identity}")
    expect(Coordinator::Shared::Types::InternalCommandId[command_id]).to eq(command_id)
    expect(described_class.call(identity)).to eq(command_id)
  end
end
