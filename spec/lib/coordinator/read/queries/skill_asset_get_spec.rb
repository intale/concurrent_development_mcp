# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::SkillAssetGet, :event_store, :read_model do
  subject(:query) { described_class.new }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:publisher) { Coordinator::Write::Operations::ExecutePublishSkillRevision.new(event_store:) }

  it "round-trips one passive binary asset from the current projected revision" do
    content = "\x00\x01skill\xff".b
    result = publisher.call(
      command_id: "cmd-asset-1",
      actor: { kind: "user", id: "user-1" },
      name: "binary-helper",
      scope: "project:alpha",
      expected_revision: 0,
      description: "Carries a binary fixture",
      instructions: "Fetch the fixture when it is needed.",
      assets: [
        {
          path: "fixtures/input.bin",
          executable: false,
          content: {
            encoding: "binary",
            media_type: "application/octet-stream",
            base64: [ content ].pack("m0")
          }
        }
      ]
    )
    expect(result).to be_success
    reference = result.value!.data.publication_event
    event = event_store.read_at(
      Coordinator::Write::StreamFactory.new.skill(result.value!.data.skill_id),
      reference.stream_revision
    )
    Coordinator::Read::Projectors::SkillsV1.new.call(event)

    available = query.call(
      name: "binary-helper",
      scope: "project:alpha",
      path: "fixtures/input.bin"
    ).value!
    missing = query.call(
      name: "binary-helper",
      scope: "project:alpha",
      path: "fixtures/missing.bin"
    ).value!

    expect(available).to have_attributes(status: "ok")
    expect(available.data.asset).to have_attributes(
      revision: 1,
      encoding: "binary",
      base64: [ content ].pack("m0"),
      byte_size: content.bytesize,
      executable: false
    )
    expect(available.warnings).to include(a_string_matching(/does not inspect or execute/))
    expect(missing).to have_attributes(status: "not_found")
  end

  it "pins asset content to the requested historical revision" do
    first = publish_asset(command_id: "cmd-asset-history-1", expected_revision: 0, content: "one")
    second = publish_asset(command_id: "cmd-asset-history-2", expected_revision: 1, content: "two")
    projector = Coordinator::Read::Projectors::SkillsV1.new
    projector.call(first)
    projector.call(second)

    historical = query.call(
      name: "binary-helper",
      scope: "project:alpha",
      path: "fixtures/input.bin",
      revision: 1
    ).value!

    expect(historical).to have_attributes(status: "ok")
    expect(historical.data.asset).to have_attributes(
      revision: 1,
      base64: [ "one" ].pack("m0")
    )
  end

  def publish_asset(command_id:, expected_revision:, content:)
    result = publisher.call(
      command_id:,
      actor: { kind: "user", id: "user-1" },
      name: "binary-helper",
      scope: "project:alpha",
      expected_revision:,
      description: "Carries a binary fixture",
      instructions: "Fetch the fixture when it is needed.",
      assets: [
        {
          path: "fixtures/input.bin",
          executable: false,
          content: {
            encoding: "binary",
            media_type: "application/octet-stream",
            base64: [ content ].pack("m0")
          }
        }
      ]
    )
    expect(result).to be_success
    reference = result.value!.data.publication_event
    event_store.read_at(
      Coordinator::Write::StreamFactory.new.skill(result.value!.data.skill_id),
      reference.stream_revision
    )
  end
end
