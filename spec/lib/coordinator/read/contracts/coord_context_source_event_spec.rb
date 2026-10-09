# frozen_string_literal: true

RSpec.describe Coordinator::Read::Contracts::CoordContextSourceEvent do
  subject(:contract) { described_class.new }

  it "accepts current granular intentions on their own stream" do
    result = contract.call(source(
      event_type: "ResourceWorkIntentionDeclared", schema_version: 1,
      stream_context: "DevelopmentCoordination", stream_name: "ResourceWorkIntention"
    ))

    expect(result).to be_success
  end

  it "rejects all retired WriteSet facts instead of advertising them to subscriptions" do
    %w[WriteSetReserved WriteSetExpanded WriteSetRenewed WriteSetReleased].each do |type|
      result = contract.call(source(event_type: type, schema_version: 2))

      expect(result).to be_failure
      expect(described_class::EVENT_TYPES).not_to include(type)
    end
  end

  it "requires the current Attempt schema and matching source stream" do
    expect(contract.call(source(event_type: "AttemptStarted", schema_version: 2))).to be_success
    expect(contract.call(source(event_type: "AttemptStarted", schema_version: 1))).to be_failure
    expect(contract.call(source(event_type: "AttemptStarted", schema_version: 2, stream_name: "WorkItem")))
      .to be_failure
  end

  def source(**changes)
    {
      event_type: "AttemptStarted", schema_version: 2,
      stream_context: "DevelopmentExecution", stream_name: "Attempt",
      stream_id: SecureRandom.uuid_v7, stream_revision: 0
    }.merge(changes)
  end
end
