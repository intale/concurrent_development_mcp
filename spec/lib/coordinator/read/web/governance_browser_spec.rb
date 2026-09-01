# frozen_string_literal: true

RSpec.describe Coordinator::Read::Web::Queries::GovernanceBrowser, :read_model do
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000081" }
  let(:other_repository_id) { "018f0f4d-4e45-7abc-8def-000000000082" }
  let(:change_set_id) { "CS-governance-browser" }
  let(:work_item_id) { "W-governance-browser" }
  let(:attempt_id) { "A-governance-browser-history" }

  before do
    create(
      :coordinator_read_repository,
      repository_id:,
      repository_key: "governance-browser",
      scope: "project:governance-browser",
      display_name: "Governance browser"
    )
    context = create(
      :coordinator_read_coord_context,
      change_set_id:,
      work_item_id:,
      repository_id:
    )
    context.update!(document: context.document.merge("attempts" => []))
    create(:coordinator_read_attempt_history, attempt_id:, change_set_id:, work_item_id:)

    create(
      :coordinator_read_decision_definition,
      decision_id: "D-direct",
      repository_id:,
      topic_id: "testing.framework"
    )
    create(
      :coordinator_read_decision_definition,
      decision_id: "D-history",
      repository_id: nil,
      attempt_id:,
      topic_id: "testing.framework"
    )
    create(
      :coordinator_read_decision_definition,
      decision_id: "D-other",
      repository_id: other_repository_id,
      topic_id: "testing.framework"
    )

    create(
      :coordinator_read_user_utterance,
      message_id: "M-project-guidance",
      conversation_id: "C-project-guidance",
      text: "Use the approved testing boundary.",
      anchors: guidance_anchors(repository_ids: [ repository_id ])
    )
    create(
      :coordinator_read_decision_interpretation,
      interpretation_id: "I-project-guidance",
      message_id: "M-project-guidance",
      stream_revision: 1
    )
    create(
      :coordinator_read_user_utterance,
      message_id: "M-other-guidance",
      conversation_id: "C-other-guidance",
      anchors: guidance_anchors(repository_ids: [ other_repository_id ])
    )

    create(
      :coordinator_read_agent_choice,
      :accepted,
      choice_id: "CHO-project",
      context: choice_context(repository_id:, attempt_id:)
    )
    create(
      :coordinator_read_agent_choice,
      :accepted,
      choice_id: "CHO-other",
      context: choice_context(repository_id: other_repository_id, attempt_id: "A-other")
    )
    create(
      :coordinator_read_agent_choice_impact,
      assessment_id: "choice-impact-v1:#{'1' * 64}",
      choice_id: "CHO-project",
      attempt_id:,
      event_global_position: 801
    )

    create(:coordinator_read_command_receipt, command_id: "cmd-a", tool_name: "change_set_create")
    create(:coordinator_read_command_receipt, command_id: "cmd-b", tool_name: "work_item_create")
  end

  it "returns bounded project governance without leaking unrelated projections" do
    first = query.catalog(repository_id:, first: 1)

    expect(first.project).to have_attributes(repository_id:, display_name: "Governance browser")
    expect(first.decisions.items.map(&:decision_id)).to eq([ "D-direct" ])
    expect(first.decisions).to have_attributes(has_more: true, next_decision_id: "D-direct")
    expect(first.guidance.items.map(&:message_id)).to eq([ "M-project-guidance" ])
    expect(first.choices.items.map(&:choice_id)).to eq([ "CHO-project" ])
    expect(first.impacts.items.map(&:assessment_id)).to eq([ "choice-impact-v1:#{'1' * 64}" ])

    second = query.catalog(repository_id:, first: 1, after_decision_id: first.decisions.next_decision_id)
    expect(second.decisions.items.map(&:decision_id)).to eq([ "D-history" ])
  end

  it "returns typed Decision, guidance interpretation, and choice impact details" do
    decision = query.decision(repository_id:, decision_id: "D-history")
    guidance = query.guidance(repository_id:, message_id: "M-project-guidance")
    choice = query.choice(repository_id:, choice_id: "CHO-project")

    expect(decision.decision).to have_attributes(decision_id: "D-history")
    expect(decision.membership_bases).to eq([ "attempt" ])
    expect(guidance.guidance).to have_attributes(text: "Use the approved testing boundary.")
    expect(guidance.interpretations.interpretations.map(&:interpretation_id)).to eq(
      [ "I-project-guidance" ]
    )
    expect(choice.choice).to have_attributes(choice_id: "CHO-project", observation_status: "accepted")
    expect(choice.impacts.items.map(&:choice_id)).to eq([ "CHO-project" ])
  end

  it "keeps command receipts global, typed, bounded, and filterable" do
    page = query.receipts(first: 1, tool_name: "change_set_create")
    receipt = query.receipt(command_id: "cmd-a")

    expect(page.items.map(&:command_id)).to eq([ "cmd-a" ])
    expect(page).to have_attributes(has_more: false, next_command_id: nil)
    expect(receipt.receipt).to have_attributes(
      command_id: "cmd-a",
      tool_name: "change_set_create",
      summary: "ChangeSet created."
    )
  end

  it "rejects malformed cursors and isolates project-scoped details" do
    expect do
      query.catalog(
        repository_id:,
        after_impact_global_position: 1,
        after_impact_assessment_id: nil
      )
    end.to raise_error(Coordinator::Read::Web::GovernanceBrowserQueryError)

    expect(query.decision(repository_id:, decision_id: "D-other")).to be_nil
    expect(query.guidance(repository_id:, message_id: "M-other-guidance")).to be_nil
    expect(query.choice(repository_id:, choice_id: "CHO-other")).to be_nil
  end

  def query
    described_class.new
  end

  def guidance_anchors(repository_ids:)
    {
      "repository_ids" => repository_ids,
      "change_set_id" => nil,
      "work_item_id" => nil,
      "attempt_id" => nil
    }
  end

  def choice_context(repository_id:, attempt_id:)
    {
      "workspace_id" => nil,
      "repository_id" => repository_id,
      "change_set_id" => change_set_id,
      "work_item_id" => work_item_id,
      "attempt_id" => attempt_id,
      "phase" => "implementation",
      "language" => "ruby",
      "paths" => [ "app/models/order.rb" ],
      "environment" => "test",
      "agent_role" => "implementer"
    }
  end
end
