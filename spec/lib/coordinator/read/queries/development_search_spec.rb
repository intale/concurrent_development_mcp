# frozen_string_literal: true

RSpec.describe "Development search read query", :read_model do
  subject(:query) { Coordinator::Container["queries.development_search"] }

  def input(**options)
    { fields: [ { field: "skill.instructions", query: { match: "contains", value: "checkpoint" } } ], **options }
  end

  it "returns a typed immediate page with native timestamps, exact evidence and pinned retrieval" do
    skill = create(:coordinator_read_skill)
    revision = create(:coordinator_read_skill_revision, skill:, instructions: "Use checkpoint context.")
    result = query.call(input).value!

    expect(result).to have_attributes(status: "ok", command_id: nil, receipt: nil, context_token: nil)
    expect(result.data).to be_a(Coordinator::Read::QueryResultV1::SearchPageData)
    item = result.data.page.items.sole
    expect(item).to have_attributes(entity_type: "skill", entity_id: skill.skill_id, updated_at: skill.updated_at.utc.iso8601(6))
    expect(item.provenance).to have_attributes(source_table: "skill_revisions", source_id: revision.id.to_s)
    expect(item.matches.sole).to have_attributes(field: "skill.instructions", path: [ "instructions" ])
    expect(item.retrieval_actions.sole.to_h).to eq(tool: "skill_get", arguments: { name: skill.name, scope: skill.scope, revision: 1 })
    expect(result.warnings.join(" ")).to include("stale", "passive", "live")
  end

  it "returns typed empty pages for absent or strictly filtered projections" do
    result = query.call(input(filters: { scope: "project:absent" })).value!
    expect(result).to have_attributes(status: "ok")
    expect(result.data.page).to have_attributes(items: [], has_more: false, cursor: nil)
  end

  it "rejects semantic input and mismatched cursors without accepting arbitrary search capabilities" do
    invalid = query.call(fields: [ { field: "skill.instructions", query: { operator: "or", operands: [
      { match: "contains", value: "foo" }, { operator: "not", operands: [ { match: "contains", value: "bar" } ] }
    ] } } ]).value!
    expect(invalid).to have_attributes(status: "invalid")
    expect(invalid.data).to have_attributes(code: "invalid_input")

    2.times do
      skill = create(:coordinator_read_skill)
      create(:coordinator_read_skill_revision, skill:, instructions: "checkpoint")
    end
    first = query.call(input(limit: 1)).value!.data.page
    invalid_cursor = query.call(input(cursor: first.cursor, filters: { scope: "project:other" })).value!
    expect(invalid_cursor).to have_attributes(status: "invalid")
    expect(invalid_cursor.data).to have_attributes(code: "invalid_cursor")
  end
end
