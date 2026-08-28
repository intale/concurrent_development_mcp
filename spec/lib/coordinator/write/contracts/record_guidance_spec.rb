# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::RecordGuidance do
  subject(:contract) { described_class.new }

  let(:valid_input) do
    {
      "command_id" => "cmd-guidance-1",
      "actor" => { "kind" => "agent", "id" => "host-1" },
      "message_id" => "M-1",
      "conversation_id" => "C-1",
      "source" => "mcp_client",
      "text" => "Do not use Redis in billing.",
      "anchors" => {
        "repository_ids" => [ RepositoryScenario::DEFAULT_REPOSITORY_ID ],
        "change_set_id" => "CS-1",
        "work_item_id" => nil,
        "attempt_id" => nil
      }
    }
  end

  it "normalizes the strict public evidence shape" do
    result = contract.call(valid_input)

    expect(result).to be_success
    expect(result.to_h).to include(
      message_id: "M-1",
      conversation_id: "C-1",
      source: "mcp_client",
      text: "Do not use Redis in billing."
    )
    expect(result.to_h.fetch(:anchors)).to eq(
      repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ],
      change_set_id: "CS-1",
      work_item_id: nil,
      attempt_id: nil
    )
  end

  it "accepts explicit agent-forwarded attribution without requiring an anchor" do
    result = contract.call(
      valid_input.merge(
        "source" => "agent_forwarded",
        "anchors" => {
          "repository_ids" => [],
          "change_set_id" => nil,
          "work_item_id" => nil,
          "attempt_id" => nil
        }
      )
    )

    expect(result).to be_success
  end

  it "rejects unknown fields, invalid provenance, invalid IDs, and invalid text" do
    result = contract.call(
      valid_input.merge(
        "unexpected" => true,
        "message_id" => "bad id",
        "conversation_id" => "bad id",
        "source" => "trusted_user",
        "text" => " \0 ",
        "anchors" => valid_input.fetch("anchors").merge(
          "repository_ids" => [ "Billing", "Billing" ],
          "change_set_id" => "bad id"
        )
      )
    )

    expect(result).to be_failure
    expect(result.errors.to_h.keys).to include(
      :unexpected,
      :message_id,
      :conversation_id,
      :source,
      :text,
      :anchors
    )
  end
end
