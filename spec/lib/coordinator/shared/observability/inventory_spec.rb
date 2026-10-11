# frozen_string_literal: true

RSpec.describe Coordinator::Shared::Observability::Inventory do
  subject(:inventory) { Coordinator::Container["observability.inventory"] }

  let(:definitions) do
    %w[process_managers task_results read_models].flat_map do |set|
      Coordinator::Container["subscription_registrations.#{set}"].map(&:definition)
    end
  end

  it "derives complete coverage from the live tool and subscription registries" do
    expect(inventory.tool_names).to match_array(Coordinator::Mcp::ToolRegistry.all.map(&:tool_name))
    expect(inventory.subscription_definitions).to match_array(definitions)
    expect(definitions.map(&:identity).uniq.length).to eq(definitions.length)
    expect(inventory.rpc_method_names).to include("server/discover", "tools/list", "tools/call", "tasks/get", "tasks/update", "tasks/cancel")
  end

  it "keeps all known tool names and bounds unknown caller-controlled names" do
    inventory.tool_names.each do |name|
      expect(inventory.mcp_attributes(method: "tools/call", tool_name: name)).to eq(
        "rpc.method" => "tools/call", "mcp.tool.name" => name
      )
    end

    expect(inventory.mcp_attributes(method: "tools/call", tool_name: "secret-request-id")).to eq(
      "rpc.method" => "tools/call", "mcp.tool.name" => "unknown"
    )
    expect(inventory.mcp_attributes(method: "invented/private-key", tool_name: "secret")).to eq(
      "rpc.method" => "unknown", "mcp.tool.name" => "none"
    )
  end

  it "permits only registered subscription identities and their filtered event types" do
    definitions.each do |definition|
      definition.event_types.each do |event_type|
        expect(inventory.subscription_attributes(definition:, event_type:)).to eq(
          "subscription.set" => definition.set_name,
          "subscription.name" => definition.subscription_name,
          "event.type" => event_type
        )
      end
      expect(inventory.subscription_attributes(definition:, event_type: "arbitrary-secret").fetch("event.type")).to eq("unknown")
    end
  end

  it "does not expose an unregistered subscription through metric labels" do
    definition = Coordinator::Shared::Subscriptions::Definition.new(
      set_name: "caller-set", subscription_name: "caller-name", stream_context: "test",
      stream_name: "test", event_types: [ "CallerEvent" ]
    )

    expect(inventory.subscription_attributes(definition:, event_type: "CallerEvent")).to eq(
      "subscription.set" => "unknown", "subscription.name" => "unknown", "event.type" => "unknown"
    )
  end
end
