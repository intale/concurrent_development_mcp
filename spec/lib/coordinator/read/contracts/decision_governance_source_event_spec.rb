# frozen_string_literal: true

RSpec.describe Coordinator::Read::Contracts::DecisionGovernanceSourceEvent do
  subject(:contract) { described_class.new }

  it "accepts only the current schema of each decision, slot and membership fact" do
    described_class::EVENT_SCHEMAS.each do |event_type, (stream_name, versions)|
      input = {
        event_type:, schema_version: versions.sole, stream_context: "HumanGuidance",
        stream_name:, stream_id: SecureRandom.uuid_v7, stream_revision: 0,
        actor_kind: "orchestrator", actor_id: "guidance-host"
      }
      expect(contract.call(input)).to be_success
      expect(contract.call(input.merge(schema_version: versions.sole == 2 ? 1 : 2)).errors.to_h).to have_key(:schema_version)
    end
  end

  it "rejects the retired whole-partition snapshot event" do
    expect(contract.call(event_type: "DecisionPartitionAdvanced").errors.to_h).to have_key(:event_type)
  end
end
