# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projections::CoordContextStateLoader do
  subject(:loader) { described_class.new }

  it "compacts terminal write-set details before enforcing the current projection schema" do
    document = Coordinator::Read::Projections::CoordContextStateV1.initial.to_h.merge(
      attempts: [
        {
          attempt_id: "ATT-terminal",
          change_set_id: "CS-terminal",
          work_item_id: "WI-terminal",
          agent_id: "agent-terminal",
          base_snapshots: [
            {
              repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
              object_format: "sha1",
              commit_oid: "a" * 40
            }
          ],
          status: "abandoned",
          authorized_at: "2026-08-29T10:00:00.000000Z",
          started_at: "2026-08-29T10:00:01.000000Z",
          write_set: { removed_projection_shape: true },
          selected_candidate_id: nil,
          selected_candidate_event: nil,
          completed_at: nil,
          abandonment_reason: "superseded",
          abandoned_at: "2026-08-29T10:01:00.000000Z"
        }
      ]
    )

    state = loader.call(JSON.parse(JSON.generate(document)))

    expect(state.attempts.sole).to have_attributes(
      status: "abandoned",
      write_set: nil,
      abandonment_reason: "superseded"
    )
  end
end
