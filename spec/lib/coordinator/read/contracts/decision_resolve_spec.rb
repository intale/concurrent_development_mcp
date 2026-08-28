# frozen_string_literal: true

RSpec.describe Coordinator::Read::Contracts::DecisionResolve do
  subject(:contract) { described_class.new }

  let(:input) do
    {
      topic_id: "testing.framework",
      context: {
        workspace_id: nil,
        repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
        change_set_id: "CS-1",
        work_item_id: "W-1",
        attempt_id: "A-1",
        phase: "implementation",
        language: "ruby",
        paths: [ "spec/models/order_spec.rb" ],
        environment: nil,
        agent_role: "implementer"
      }
    }
  end

  it "accepts extensible Decision topics and supported phases" do
    expect(contract.call(input)).to be_success
    expect(
      contract.call(
        input.merge(
          topic_id: "candidate.impact_policy",
          context: input.fetch(:context).merge(phase: "verification")
        )
      )
    ).to be_success
  end

  it "rejects malformed topics, dimensions, identifiers, phases, and bounds" do
    result = contract.call(
      input.merge(
        topic_id: "testing required suites",
        unexpected: true,
        context: input.fetch(:context).merge(
          repository_id: "Billing Team",
          phase: "coding",
          paths: Array.new(33, "spec/models/order_spec.rb"),
          branch: "main"
        )
      )
    )

    expect(result).to be_failure
    expect(result.errors.to_h).to include(:topic_id, :context, :unexpected)
    expect(result.errors.to_h.fetch(:context)).to include(:branch)

    semantic_result = contract.call(
      input.merge(
        context: input.fetch(:context).merge(
          repository_id: "Billing Team",
          phase: "coding",
          paths: Array.new(33, "spec/models/order_spec.rb")
        )
      )
    )
    expect(semantic_result.errors.to_h.fetch(:context)).to include(:repository_id, :phase, :paths)
  end
end
