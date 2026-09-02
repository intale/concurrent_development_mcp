# frozen_string_literal: true

RSpec.describe Coordinator::Read::Web::Queries::GovernanceBrowser, :read_model do
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000081" }
  let(:member_repository_id) { "018f0f4d-4e45-7abc-8def-000000000083" }
  let(:other_repository_id) { "018f0f4d-4e45-7abc-8def-000000000082" }
  let(:project_scope) { "project:governance-browser" }
  let(:project_ref) { Coordinator::Read::Web::ProjectReference.new.encode(scope: project_scope) }
  let(:change_set_id) { "CS-governance-browser" }
  let(:work_item_id) { "W-governance-browser" }
  let(:attempt_id) { "A-governance-browser-history" }
  let(:impact_id) { "choice-impact-v1:#{'1' * 64}" }

  before do
    create_project(repository_id, project_scope)
    create_project(member_repository_id, project_scope)
    create_project(other_repository_id, "project:other-governance")
    create_coordination_history
    create_governance_facts
    create_receipts
  end

  it "serves focused bounded collections across every Repository member of the exact Project" do
    first = query.decisions(project_ref:, first: 1)
    guidance = query.guidance_list(project_ref:, first: 20, source: "agent_forwarded")
    choices = query.choices(project_ref:, first: 20, status: "accepted")
    impacts = query.impacts(project_ref:, first: 20, outcome: "invalidated")

    expect(first.items.map(&:decision_id)).to eq([ "D-history" ])
    expect(first).to have_attributes(has_more: true, next_decision_id: "D-history")
    expect(guidance.items.map(&:message_id)).to eq([ "M-project-guidance" ])
    expect(choices.items.map(&:choice_id)).to eq([ "CHO-project" ])
    expect(impacts.items.map(&:assessment_id)).to eq([ impact_id ])

    second = query.decisions(project_ref:, first: 1, after_decision_id: first.next_decision_id)
    expect(second.items.map(&:decision_id)).to eq([ "D-member" ])
  end

  it "returns project-bound Decision, Guidance, AgentChoice, and impact details" do
    decision = query.decision(project_ref:, decision_id: "D-history")
    guidance = query.guidance(project_ref:, message_id: "M-project-guidance")
    choice = query.choice(project_ref:, choice_id: "CHO-project")
    impact = query.impact(project_ref:, assessment_id: impact_id)

    expect(decision.decision).to have_attributes(decision_id: "D-history")
    expect(decision.membership_bases).to eq([ "attempt" ])
    expect(guidance.guidance).to have_attributes(text: "Use the approved testing boundary.")
    expect(guidance.interpretations.interpretations.map(&:interpretation_id)).to eq(
      [ "I-project-guidance" ]
    )
    expect(choice.choice).to have_attributes(choice_id: "CHO-project", observation_status: "accepted")
    expect(choice.impacts.items.map(&:assessment_id)).to eq([ impact_id ])
    expect(impact.impact).to have_attributes(assessment_id: impact_id, choice_id: "CHO-project")
  end

  it "rejects partial impact cursors and isolates details outside the Project scope" do
    expect do
      query.impacts(project_ref:, after_global_position: 1, after_assessment_id: nil)
    end.to raise_error(Coordinator::Read::Web::GovernanceBrowserQueryError)

    expect(query.decision(project_ref:, decision_id: "D-other")).to be_nil
    expect(query.guidance(project_ref:, message_id: "M-other-guidance")).to be_nil
    expect(query.choice(project_ref:, choice_id: "CHO-other")).to be_nil
    expect(query.impact(project_ref:, assessment_id: "choice-impact-v1:#{'2' * 64}")).to be_nil
  end

  it "keeps command receipts global, typed, bounded, and compatible with current tool names" do
    page = query.receipts(first: 1, tool_name: "change_set_create")
    receipt = query.receipt(command_id: "cmd-a")

    expect(page.items.map(&:command_id)).to eq([ "cmd-a" ])
    expect(page).to have_attributes(has_more: false, next_command_id: nil)
    expect(receipt.receipt).to have_attributes(
      command_id: "cmd-a",
      tool_name: "change_set_create",
      summary: "ChangeSet created.",
      next_action_tools: [ "development_artifact_get" ]
    )
  end

  it "bounds malformed completion data without coupling Project governance availability to receipts" do
    record = Coordinator::Read::CommandReceipt.find("cmd-a")
    record.update!(
      completion: record.completion.merge(
        "next_actions" => [ { "tool" => "not a tool", "arguments" => {} } ]
      )
    )

    expect(query.decisions(project_ref:, first: 20).items).not_to be_empty
    expect { query.receipt(command_id: "cmd-a") }
      .to raise_error(Coordinator::Read::Web::GovernanceBrowserReadError) do |error|
        expect(error.details).to eq(
          entity: "command_receipt",
          command_id: "cmd-a",
          reason: "invalid_completion"
        )
      end
  end

  it "detects divergence between searchable receipt columns and validated completion facts" do
    Coordinator::Read::CommandReceipt.find("cmd-a").update_column(:summary, "Diverged summary")

    expect { query.receipt(command_id: "cmd-a") }
      .to raise_error(Coordinator::Read::Web::GovernanceBrowserReadError) do |error|
        expect(error.details.fetch(:reason)).to eq("projection_mismatch")
      end
  end

  def query
    described_class.new
  end

  def create_project(id, scope)
    create(
      :coordinator_read_repository,
      repository_id: id,
      repository_key: "governance-#{id}",
      scope:,
      display_name: "Governance browser"
    )
  end

  def create_coordination_history
    context = create(
      :coordinator_read_coord_context,
      change_set_id:,
      work_item_id:,
      repository_id:
    )
    context.update!(document: context.document.merge("attempts" => []))
    create(:coordinator_read_attempt_history, attempt_id:, change_set_id:, work_item_id:)
  end

  def create_governance_facts
    create(
      :coordinator_read_decision_definition,
      decision_id: "D-member",
      repository_id: member_repository_id,
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
      anchors: guidance_anchors(member_repository_id)
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
      anchors: guidance_anchors(other_repository_id)
    )
    create(
      :coordinator_read_agent_choice,
      :accepted,
      choice_id: "CHO-project",
      context: choice_context(member_repository_id, attempt_id)
    )
    create(
      :coordinator_read_agent_choice,
      :accepted,
      choice_id: "CHO-other",
      context: choice_context(other_repository_id, "A-other")
    )
    create(
      :coordinator_read_agent_choice_impact,
      assessment_id: impact_id,
      choice_id: "CHO-project",
      attempt_id:,
      event_global_position: 801
    )
    create(
      :coordinator_read_agent_choice_impact,
      assessment_id: "choice-impact-v1:#{'2' * 64}",
      choice_id: "CHO-other",
      attempt_id: "A-other",
      event_global_position: 802
    )
  end

  def create_receipts
    receipt = create(:coordinator_read_command_receipt, command_id: "cmd-a", tool_name: "change_set_create")
    receipt.update!(
      completion: receipt.completion.merge(
        "next_actions" => [
          {
            "tool" => "development_artifact_get",
            "arguments" => { "artifact_id" => "018f0f4d-4e45-7abc-8def-000000000211" }
          }
        ]
      )
    )
    create(:coordinator_read_command_receipt, command_id: "cmd-b", tool_name: "work_item_create")
  end

  def guidance_anchors(id)
    {
      "repository_ids" => [ id ],
      "change_set_id" => nil,
      "work_item_id" => nil,
      "attempt_id" => nil
    }
  end

  def choice_context(id, choice_attempt_id)
    {
      "workspace_id" => nil,
      "repository_id" => id,
      "change_set_id" => change_set_id,
      "work_item_id" => work_item_id,
      "attempt_id" => choice_attempt_id,
      "phase" => "implementation",
      "language" => "ruby",
      "paths" => [ "app/models/order.rb" ],
      "environment" => "test",
      "agent_role" => "implementer"
    }
  end
end
