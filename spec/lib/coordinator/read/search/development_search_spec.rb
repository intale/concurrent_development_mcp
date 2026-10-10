# frozen_string_literal: true

RSpec.describe Coordinator::Read::Repositories::DevelopmentSearch, read_model: true do
  let(:codec) { Coordinator::Read::Search::CursorCodec.new(secret: "search-test-cursor-integrity") }
  let(:builder) { Coordinator::Read::Search::QueryBuilder.new(cursor_codec: codec) }
  subject(:repository) { described_class.new(cursor_codec: codec) }

  def literal(value, match: "contains", **options)
    { match:, value:, **options }
  end

  def search(*fields, **options)
    query = builder.call(fields: fields.map { |field, expression| { field:, query: expression } }, **options).value!
    repository.page(query).value!
  end

  def skill(instructions, **attributes)
    record = create(:coordinator_read_skill, **attributes)
    create(:coordinator_read_skill_revision, skill: record, instructions:)
    record
  end

  it "evaluates four literal positions and full-field equality with default and explicit case semantics" do
    skill("foo checkpoint baz", name: "foo")
    skill("FOO checkpoint BAZ", name: "foobar")
    expect(search([ "skill.name", literal("foo", match: "equals") ]).items.length).to eq(1)
    expect(search([ "skill.instructions", literal("foo", match: "starts_with") ]).items.length).to eq(1)
    expect(search([ "skill.instructions", literal("BAZ", match: "ends_with") ]).items.length).to eq(1)
    expect(search([ "skill.instructions", literal("FOO", case_sensitive: false) ]).items.length).to eq(2)
    expect(search([ "skill.instructions", literal("foo checkpoint baz", match: "equals", case_sensitive: false) ]).items.length).to eq(2)
  end

  it "matches literal percent, underscore, backslash, quotes, newlines and Unicode without serialization" do
    record = skill("literal foo%_\\bar 'quote'\n日本語")
    skill("literal fooXYbar 'quote'\\n日本語")
    result = search([ "skill.instructions", literal("foo%_\\bar 'quote'\n日本語") ])
    expect(result.items.map(&:entity_id)).to eq([ record.skill_id ])
    expect(result.items.first.matches.first.excerpt).to include("\n日本語")
  end

  it "applies Boolean conjunction and exclusions within the same raw array element" do
    create(:coordinator_read_development_artifact, labels: [ "bar middle baz", "irrelevant" ])
    create(:coordinator_read_development_artifact, labels: [ "bar middle", "middle baz" ])
    create(:coordinator_read_development_artifact, labels: [ "bar excluded baz" ])
    expression = { operator: "and", operands: [ literal("bar", match: "starts_with"), literal("baz", match: "ends_with"),
      { operator: "not", operands: [ literal("excluded") ] } ] }
    page = search([ "development_artifact.labels", expression ])
    expect(page.items.length).to eq(1)
    expect(page.items.first.matches.first.path).to eq(%w[labels 0])
    expect(page.items.first.matches.first.excerpt).to eq("bar middle baz")
  end

  it "searches a complete large-body tail and never searches binary content as text" do
    skill("a" * 100_000 + "\nunique-tail 日本語")
    record = create(:coordinator_read_skill)
    create(:coordinator_read_skill_revision, skill: record)
    create(:coordinator_read_skill_asset, :binary, skill: record, path: "unique-tail.bin")
    page = search([ "skill.instructions", literal("unique-tail 日本語") ], [ "skill_asset.content", literal("factory") ])
    expect(page.items.length).to eq(1)
    expect(page.items.first.matches.first.excerpt).to include("unique-tail 日本語")
    expect(page.items.first.matches.first.excerpt.length).to be <= 240
    expect(page.items.first.matches.first.excerpt_offset).to be > 99_000
    expect(search([ "skill_asset.path", literal("unique-tail") ]).items.length).to eq(1)
  end

  it "intersects exact scope and repository membership without adding global or other scoped skills" do
    home = create(:coordinator_read_repository, scope: "project:home")
    work = create(:coordinator_read_repository, scope: "project:work")
    matched = skill("checkpoint", name: "same-name", scope: home.scope)
    skill("checkpoint", name: "same-name", scope: work.scope)
    skill("checkpoint", scope: "global")
    expect(search([ "skill.instructions", literal("checkpoint") ], filters: { scope: home.scope, repository_id: home.repository_id }).items.map(&:entity_id)).to eq([ matched.skill_id ])
    expect(search([ "skill.instructions", literal("checkpoint") ], filters: { scope: home.scope, repository_id: work.repository_id }).items).to be_empty
    expect(search([ "skill.instructions", literal("checkpoint") ], filters: { entity_types: [ "resource" ] }).items).to be_empty
  end

  it "deduplicates overlapping fields and paginates ties without skipping matching evidence" do
    records = 5.times.map { |index| skill("checkpoint", name: "checkpoint-#{index}", updated_at: Time.utc(2026, 10, 10, 8)) }
    fields = [ [ "skill.name", literal("checkpoint") ], [ "skill.instructions", literal("checkpoint") ] ]
    all = []
    cursor = nil
    loop do
      page = search(*fields, limit: 2, **(cursor ? { cursor: } : {}))
      expect(page.items.length).to be <= 2
      expect(page.items.map { _1.matches.map(&:field) }).to all(eq(%w[skill.instructions skill.name]))
      all.concat(page.items.map(&:entity_id))
      break unless page.has_more

      cursor = page.cursor
    end
    expect(all).to eq(records.map(&:skill_id).sort)
    expect(all.uniq.length).to eq(5)
  end

  it "aliases the matching latest observation with the head but keeps older observations distinct" do
    artifact = create(:coordinator_read_development_artifact, title: "checkpoint", content_text: "checkpoint body")
    old = create(:coordinator_read_development_artifact_observation, artifact:, observed_global_position: 1)
    latest = create(:coordinator_read_development_artifact_observation, artifact:, observed_global_position: 2)
    page = search([ "development_artifact.title", literal("checkpoint") ], [ "development_artifact.content", literal("checkpoint") ])
    expect(page.items.map(&:document_id)).to contain_exactly("current:#{artifact.artifact_id}", "observation:#{old.observation_id}")
    expect(page.items.map { _1.matches.map(&:field) }).to all(eq(%w[development_artifact.content development_artifact.title]))
    current = page.items.find { _1.document_id.start_with?("current:") }
    expect(current.retrieval.fetch("arguments").fetch("observation_id")).to eq(latest.observation_id)
  end

  it "serves both divergent current-head and retained observation text without a freshness gate" do
    artifact = create(:coordinator_read_development_artifact, content_text: "checkpoint current")
    observation = create(:coordinator_read_development_artifact_observation, artifact:, content_text: "checkpoint retained")
    page = search([ "development_artifact.content", literal("checkpoint") ])
    expect(page.items.map(&:document_id)).to contain_exactly("current:#{artifact.artifact_id}", "observation:#{observation.observation_id}")
    expect(page.items.map { _1.matches.first.excerpt }).to contain_exactly("checkpoint current", "checkpoint retained")
  end

  it "searches current WorkItem goals and raw criteria using their own identity" do
    context = create(:coordinator_read_coord_context)
    work_item = context.document.fetch("work_items").first
    page = search([ "work_item.goal", literal("factory") ], [ "work_item.acceptance_criteria", literal("verifiable") ])
    expect(page.items.map(&:entity_id)).to eq([ work_item.fetch("work_item_id") ])
    expect(page.items.first.updated_at).to eq(context.updated_at.utc.iso8601(6))
    expect(page.items.first.matches.map(&:field)).to eq(%w[work_item.acceptance_criteria work_item.goal])
  end

  it "searches the remaining catalogue families and retains their canonical retrieval actions" do
    create(:coordinator_read_resource, normalized_path: "lib/needle-scalar.rb")
    create(:coordinator_read_user_utterance, text: "needle-scalar guidance")
    create(:coordinator_read_agent_choice, selected: { "option_id" => "option", "summary" => "needle-scalar choice" })
    create(:coordinator_read_decision_definition, :active, rationale: { "code" => "activated", "summary" => "needle-scalar decision" })
    fields = %w[resource.path guidance.text agent_choice.selected_summary decision.rationale].map { [ _1, literal("needle-scalar") ] }
    page = search(*fields)
    expect(page.items.map(&:entity_type)).to contain_exactly("resource", "guidance", "agent_choice", "decision")
    expect(page.items.map { _1.retrieval.fetch("tool") }).to contain_exactly("resource_get", "guidance_get", "agent_choice_get", "decision_get")
  end

  it "uses only declared Guidance, Choice and Decision repository memberships for intersecting filters" do
    home = create(:coordinator_read_repository, scope: "project:home")
    other = create(:coordinator_read_repository, scope: "project:other")
    context = create(:coordinator_read_coord_context, repository_id: home.repository_id)
    create(:coordinator_read_user_utterance, text: "needle-membership", anchors: {
      "repository_ids" => [], "change_set_id" => context.change_set_id, "work_item_id" => nil, "attempt_id" => nil
    })
    create(:coordinator_read_user_utterance, text: "needle-membership global")
    choice_context = build(:coordinator_read_agent_choice).context.merge("repository_id" => home.repository_id)
    create(:coordinator_read_agent_choice, reason_summary: "needle-membership", context: choice_context)
    create(:coordinator_read_decision_definition, :active, repository_id: home.repository_id,
      rationale: { "code" => "activated", "summary" => "needle-membership decision" })
    fields = %w[guidance.text agent_choice.reason_summary decision.rationale].map { [ _1, literal("needle-membership") ] }
    expect(search(*fields, filters: { scope: home.scope, repository_id: home.repository_id }).items.map(&:entity_type)).to contain_exactly("guidance", "agent_choice", "decision")
    expect(search(*fields, filters: { scope: home.scope, repository_id: other.repository_id }).items).to be_empty
  end

  it "rejects an oversized bounded response rather than returning a misleading partial page" do
    text = "needle " + "界" * 233
    create_list(:coordinator_read_development_artifact, 50, title: text, content_text: text,
      source_locator: text, source_revision: text, source_collector: text, labels: [ text ])
    fields = %w[title content source_locator source_revision source_collector labels].map do |field|
      { field: "development_artifact.#{field}", query: literal("needle") }
    end
    query = builder.call(fields:, limit: 50).value!
    expect(repository.page(query).failure.code).to eq("search_response_limit")
    expect(repository.page(builder.call(fields:, limit: 5).value!).value!.items.length).to eq(5)
  end

  it "has a mandatory source and field cap with parameterized literal input" do
    query = builder.call(fields: [ { field: "skill.instructions", query: literal("foo' OR TRUE --") } ], limit: 2).value!
    fragment = Coordinator::Read::Search::FieldQueryCompiler.new.call(query.fields.first, query:)
    expect(fragment.sql.scan(/LIMIT 3/).length).to eq(2)
    expect(fragment.sql).not_to include("foo' OR TRUE --")
    expect(fragment.binds).to include("%foo' OR TRUE --%")
    union = Coordinator::Read::Search::UnionCompiler.new.call([], limit: 2)
    expect(union.sql).to match(/LIMIT 3\s*\z/)
  end
end
