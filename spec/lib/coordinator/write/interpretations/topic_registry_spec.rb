# frozen_string_literal: true

RSpec.describe Coordinator::Write::Interpretations::TopicRegistry do
  it "defines the exact non-inheritable Candidate impact policy ontology" do
    definition = described_class.new.fetch("candidate.impact_policy")

    expect(definition).to have_attributes(
      parent_topic_id: "candidate.impact",
      value_schema: "string-set/v1",
      resolution_strategy: "single_choice",
      inheritable: false,
      default_modality: "must",
      default_enforcement: "disabled",
      conflict_dimension: "candidate_impact_policy",
      ontology_version: 1,
      aliases: []
    )
  end
end
