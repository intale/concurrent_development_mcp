# frozen_string_literal: true

RSpec.describe "Development search projected corpus", :read_model do
  let(:codec) { Coordinator::Read::Search::CursorCodec.new(secret: "search-corpus-integrity") }
  let(:builder) { Coordinator::Read::Search::QueryBuilder.new(cursor_codec: codec) }
  let(:repository) { Coordinator::Read::Repositories::DevelopmentSearch.new(cursor_codec: codec) }

  def search(field, value)
    query = builder.call(fields: [ { field:, query: { match: "contains", value: } } ]).value!
    repository.page(query).value!.items
  end

  def decision(value:, **attributes)
    definition = build(:coordinator_read_decision_definition).definition.deep_dup
    document = definition.fetch("document")
    document.fetch("topic")["aliases"] = [ "needle-alias" ]
    document.fetch("scope")["workspace_id"] = "needle-workspace"
    document.fetch("conditions")["tags"] = [ "needle-condition" ]
    document["value"] = document.fetch("value").merge(value)
    create(:coordinator_read_decision_definition, definition:,
      rationale: { "code" => "activated", "summary" => "needle-rationale" },
      correction_rationale: { "code" => "corrected", "summary" => "needle-correction" }, **attributes)
  end

  it "covers every advertised selector using actual stored raw values, not catalogue-derived expectations" do
    skill = create(:coordinator_read_skill, name: "needle-skill", scope: "project:needle-skill")
    create(:coordinator_read_skill_revision, skill:, description: "needle-description", instructions: "needle-instructions")
    create(:coordinator_read_skill_asset, skill:, path: "docs/needle-asset.txt", content_text: "needle-asset-body")
    create(:coordinator_read_resource, :inactive, normalized_path: "docs/needle-resource.md", unbinding_reason: "needle-unbound")
    artifact = create(:coordinator_read_development_artifact, title: "needle-title", scope: "project:needle-artifact",
      labels: [ "needle-label" ], content_text: "needle-artifact-body", source_locator: "docs/needle-locator.md",
      source_revision: "needle-source-revision", source_collector: "needle-collector")
    create(:coordinator_read_development_artifact_observation, artifact:, classification_reason: "needle-classification")
    create(:coordinator_read_user_utterance, text: "needle-guidance")
    create(:coordinator_read_agent_choice, reason_summary: "needle-reason",
      selected: { "option_id" => "rspec", "summary" => "needle-selected" },
      alternatives: [ { "option_id" => "minitest", "summary" => "needle-alternative" } ],
      assessment: { "warnings" => [ "needle-warning" ] }, invalidation: { "reason" => "needle-invalidated" })
    decision(value: { "name" => "needle-value" })
    decision(value: { "schema" => "string-set/v1", "name" => nil, "items" => [ "needle-item" ] })
    decision(value: { "schema" => "target-action/v1", "name" => nil, "target_kind" => "candidate",
      "target_id" => "needle-target", "action" => "approve" })
    create(:coordinator_read_coord_context)

    expected = {
      "skill.name" => "needle-skill", "skill.scope" => "project:needle-skill",
      "skill.description" => "needle-description", "skill.instructions" => "needle-instructions",
      "skill_asset.path" => "needle-asset", "skill_asset.content" => "needle-asset-body",
      "resource.path" => "needle-resource", "resource.kind" => "file", "resource.unbinding_reason" => "needle-unbound",
      "development_artifact.title" => "needle-title", "development_artifact.scope" => "project:needle-artifact",
      "development_artifact.kind" => "documentation", "development_artifact.labels" => "needle-label",
      "development_artifact.content" => "needle-artifact-body", "development_artifact.source_locator" => "needle-locator",
      "development_artifact.source_revision" => "needle-source-revision", "development_artifact.source_collector" => "needle-collector",
      "development_artifact.classification_reason" => "needle-classification", "guidance.text" => "needle-guidance",
      "agent_choice.choice_type" => "testing.framework", "agent_choice.reason_summary" => "needle-reason",
      "agent_choice.selected_summary" => "needle-selected", "agent_choice.alternative_summary" => "needle-alternative",
      "agent_choice.warnings" => "needle-warning", "agent_choice.invalidation_reason" => "needle-invalidated",
      "decision.topic" => "testing.framework", "decision.topic_aliases" => "needle-alias", "decision.value_name" => "needle-value",
      "decision.value_items" => "needle-item", "decision.value_action" => "approve", "decision.value_target_id" => "needle-target",
      "decision.scope" => "needle-workspace", "decision.conditions" => "needle-condition",
      "decision.rationale" => "needle-rationale", "decision.correction_rationale" => "needle-correction",
      "work_item.goal" => "factory", "work_item.acceptance_criteria" => "verifiable"
    }
    expect(expected.keys).to match_array(Coordinator::Read::Search::FieldCatalog::SELECTORS)
    expected.each do |field, value|
      hits = search(field, value)
      expect(hits).not_to be_empty, "#{field} did not match #{value.inspect}"
      expect(hits.flat_map(&:matches).map(&:field).uniq).to eq([ field ])
      expect(hits.flat_map(&:matches).map(&:excerpt)).to all(include(value))
    end
  end

  it "does not expose JSON serialization, keys, numbers, flags, technical evidence or mixed collection scalars" do
    record = decision(value: { "name" => "rspec" }, definition_digest: "needle-technical")
    definition = record.definition.deep_dup
    definition.fetch("document").fetch("conditions")["tags"] = [ "bar first", "second baz", 123456, true ]
    record.update!(definition:)
    expect(search("decision.conditions", "123456")).to be_empty
    expect(search("decision.conditions", "true")).to be_empty
    expect(search("decision.conditions", "tags")).to be_empty
    expect(search("decision.scope", "workspace_id")).to be_empty
    expect(search("decision.value_name", "needle-technical")).to be_empty
    query = builder.call(fields: [ { field: "decision.conditions", query: { operator: "and", operands: [
      { match: "contains", value: "bar" }, { match: "contains", value: "baz" }
    ] } } ]).value!
    expect(repository.page(query).value!.items).to be_empty
  end
end
