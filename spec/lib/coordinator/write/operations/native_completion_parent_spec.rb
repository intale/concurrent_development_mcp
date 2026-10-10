# frozen_string_literal: true

RSpec.describe "Specialized command completion parents", :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:actor) { { kind: "agent", id: "native-parent-agent" } }
  let(:repository_id) { RepositoryScenario.register(event_store:, key: "native-parent") }

  it "retains the last native Repository fact without including it in emitted references" do
    result = Coordinator::Write::Operations::ExecuteRegisterRepository.new(event_store:).call(
      command_id: "register-native-parent", actor:, repository_id: SecureRandom.uuid_v7,
      scope: "project:native-parent", repository_key: "native-parent",
      display_name: "Native parent", paths: [ "/projects/native-parent" ], remotes: []
    ).value!

    expect(result.terminal_event.id).to eq(result.emitted_events.last.event_id)
    expect(result.terminal_event.type).to eq("RepositoryPathAdded")
  end

  it "retains the Resource binding parent and has no new parent on a no-op resolution" do
    operation = Coordinator::Write::Operations::ExecuteResolveResource.new(event_store:)
    input = { command_id: "resolve-native-parent", actor:, repository_id:, kind: "file", path: "app.rb" }

    result = operation.call(input).value!
    replay = operation.call(input).value!

    expect(result.terminal_event.id).to eq(result.emitted_events.last.event_id)
    expect(result.terminal_event.type).to eq("ResourceBound")
    expect(replay.emitted_events).to be_empty
    expect(replay.terminal_event).to be_nil
  end

  it "retains the Resource unbinding parent and has no new parent on a no-op removal" do
    resource_id = ResourceScenario.resolve(event_store:, repository_id:, kind: "file", path: "app.rb")
    operation = Coordinator::Write::Operations::ExecuteRemoveResource.new(event_store:)
    input = { command_id: "remove-native-parent", actor:, resource_id:, reason: "removed" }

    result = operation.call(input).value!
    replay = operation.call(input).value!

    expect(result.terminal_event.id).to eq(result.emitted_events.last.event_id)
    expect(result.terminal_event.type).to eq("ResourceUnbound")
    expect(replay.emitted_events).to be_empty
    expect(replay.terminal_event).to be_nil
  end
end
