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
          media_type: "application/octet-stream",
          executable: false,
          content_base64: [ content ].pack("m0")
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
      content_base64: [ content ].pack("m0"),
      byte_size: content.bytesize,
      executable: false
    )
    expect(available.warnings).to include(a_string_matching(/does not inspect or execute/))
    expect(missing).to have_attributes(status: "not_found")
  end
end
