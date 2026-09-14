# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projections::CoordContextStateLoader do
  subject(:loader) { described_class.new }

  it "keeps an available active Attempt readable before it has a work-intention set" do
    document = Coordinator::Read::Projections::CoordContextStateV1.initial.to_h.merge(
      attempts: [
        {
          attempt_id: "ATT-active",
          change_set_id: "CS-active",
          work_item_id: "WI-active",
          agent_id: "agent-active",
          base_snapshots: [
            {
              repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
              object_format: "sha1",
              commit_oid: "a" * 40
            }
          ],
          status: "started",
          authorized_at: "2026-09-14T06:59:04.639069Z",
          started_at: "2026-09-14T06:59:04.639069Z",
          selected_candidate_id: nil,
          selected_candidate_event: nil,
          completed_at: nil,
          abandonment_reason: nil,
          abandoned_at: nil
        }
      ]
    )

    state = loader.call(JSON.parse(JSON.generate(document)))

    expect(state.attempts.sole).to have_attributes(
      status: "started",
      work_intention_set: nil
    )
  end

  it "compacts terminal work-intention details before enforcing the current projection schema" do
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
          work_intention_set: { removed_projection_shape: true },
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
      work_intention_set: nil,
      abandonment_reason: "superseded"
    )
  end
end
