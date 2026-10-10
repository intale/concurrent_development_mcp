# frozen_string_literal: true

RSpec.describe Coordinator::Read::Search::FieldCatalog do
  it "covers each approved corpus with explicit raw projection paths and retrieval tools" do
    expect(described_class::ENTITY_TYPES).to eq(%w[skill skill_asset resource development_artifact guidance agent_choice decision work_item])
    expect(described_class::SELECTORS.uniq).to eq(described_class::SELECTORS)
    expect(described_class.fetch("skill.instructions").retrieval_tool).to eq("skill_get")
    expect(described_class.fetch("resource.path").column).to eq("normalized_path")
    expect(described_class.fetch("agent_choice.alternative_summary").path).to eq([ "*", "summary" ])
    expect(described_class.fetch("decision.value_items").values).to eq("elements")
    expect(described_class.fetch("development_artifact.content").column).to eq("content_text")
    expect(described_class::SELECTORS).not_to include("resource.content", "skill.content_base64", "decision.digest")
  end
end
