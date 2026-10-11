# frozen_string_literal: true

RSpec.describe "Development search read-store text derivation", read_model: true do
  def values_for(record, field: nil)
    connection = ApplicationRecord.connection
    filter = "source_table = #{connection.quote(record.class.table_name)} AND source_id = #{connection.quote(record.id)}"
    filter += " AND field = #{connection.quote(field)}" if field
    connection.select_all("SELECT * FROM coordinator_search_values WHERE #{filter} ORDER BY field, value_path").to_a
  end

  it "keeps exact raw array values and native owner timestamps rather than escaped JSON" do
    artifact = create(:coordinator_read_development_artifact, labels: [ "foo\nbar", 'quoted "label"', "日本語" ])
    rows = values_for(artifact)
    expect(rows.map { _1.fetch("value") }).to eq([ "foo\nbar", 'quoted "label"', "日本語" ])
    expect(rows.map { _1.fetch("value_path") }).to eq(%w[{labels,0} {labels,1} {labels,2}])
    expect(rows.map { _1.fetch("updated_at") }.uniq).to eq([ artifact.updated_at ])
    expect(rows.map { _1.fetch("document_id") }.uniq).to eq([ artifact.artifact_id ])
  end

  it "derives only approved Agent Choice summaries and warnings, not option IDs or mirrored context" do
    choice = create(:coordinator_read_agent_choice, alternatives: [
      { "option_id" => "not-searchable", "summary" => "raw\nsummary" },
      { "option_id" => "other-option", "summary" => "other summary" }
    ], assessment: { "warnings" => [ "unsafe choice" ] })
    rows = values_for(choice)
    expect(rows.map { _1.fetch("value") }).to contain_exactly("raw\nsummary", "other summary", "unsafe choice")
    expect(rows.map { _1.fetch("field") }.uniq).to contain_exactly("agent_choice.alternative_summary", "agent_choice.warnings")
  end

  it "extracts individual Decision scope and condition leaves, ignoring nontext scalars" do
    decision = build(:coordinator_read_decision_definition)
    definition = decision.definition.deep_dup
    definition.fetch("document")["scope"] = { "nested" => [ "foo", "bar\nbaz", 99, false, nil ] }
    definition.fetch("document")["conditions"] = { "languages" => [ "ruby", "日本語" ] }
    decision.definition = definition
    decision.save!
    expect(values_for(decision, field: "decision.scope").map { _1.fetch("value") }).to eq([ "foo", "bar\nbaz" ])
    expect(values_for(decision, field: "decision.conditions").map { _1.fetch("value") }).to eq([ "ruby", "日本語" ])
  end

  it "preserves WorkItem identity and separates criteria within the current Context" do
    context = create(:coordinator_read_coord_context)
    rows = values_for(context)
    expect(rows.map { _1.fetch("document_id") }.uniq).to eq([ context.document.fetch("work_items").first.fetch("work_item_id") ])
    expect(rows.map { _1.fetch("value") }).to contain_exactly("Implement factory work", "The result is verifiable")
    expect(rows.map { _1.fetch("field") }).to contain_exactly("work_item.goal", "work_item.acceptance_criteria")
  end

  it "synchronizes bulk replacement and removal in the source transaction without callbacks" do
    artifact = create(:coordinator_read_development_artifact, labels: [ "old label" ])
    timestamp = Time.current
    Coordinator::Read::DevelopmentArtifact.where(artifact_id: artifact.artifact_id).update_all(labels: [ "new label" ], updated_at: timestamp)
    expect(values_for(artifact).map { _1.fetch("value") }).to eq([ "new label" ])
    expect(values_for(artifact).first.fetch("updated_at")).to be_within(0.000001).of(timestamp)
    Coordinator::Read::DevelopmentArtifact.where(artifact_id: artifact.artifact_id).delete_all
    expect(values_for(artifact)).to be_empty
  end

  it "preserves derived row identities and advances timestamps for unchanged collections on every source" do
    timestamp = Time.utc(2026, 10, 11, 10)
    records = [
      create(:coordinator_read_development_artifact),
      create(:coordinator_read_development_artifact_observation),
      create(:coordinator_read_agent_choice),
      create(:coordinator_read_decision_definition),
      create(:coordinator_read_coord_context)
    ]
    records.each do |record|
      before = values_for(record)
      expect(before).not_to be_empty
      record.class.where(record.class.primary_key => record.id).update_all(updated_at: timestamp)
      after = values_for(record)
      expect(after.map { _1.except("updated_at") }).to eq(before.map { _1.except("updated_at") })
      expect(after.map { _1.fetch("updated_at") }.uniq).to eq([ timestamp ])
    end
  end

  it "updates only changed paths, retains surviving row identities and removes vanished paths" do
    artifact = create(:coordinator_read_development_artifact, labels: [ "retained", "changed", "removed" ])
    before = values_for(artifact)
    timestamp = Time.utc(2026, 10, 11, 11)
    artifact.update_columns(labels: [ "retained", "replacement" ], updated_at: timestamp)
    after = values_for(artifact)
    expect(after.map { _1.fetch("value") }).to eq([ "retained", "replacement" ])
    expect(after.map { _1.fetch("id") }).to eq(before.first(2).map { _1.fetch("id") })
    expect(after.map { _1.fetch("updated_at") }.uniq).to eq([ timestamp ])
    artifact.update_columns(labels: [])
    expect(values_for(artifact)).to be_empty
  end

  it "excludes large bodies and unrelated context from table-specific selected inputs" do
    body = "not a collection input\n" * 50_000
    artifact = create(:coordinator_read_development_artifact, content_text: body, content_byte_size: body.bytesize)
    observation = create(:coordinator_read_development_artifact_observation, artifact:)
    choice = create(:coordinator_read_agent_choice, assessment: { "warnings" => [ "retained warning" ], "unrelated" => body })
    context = create(:coordinator_read_coord_context)
    context.update_columns(document: context.document.merge("unrelated" => body))
    [ artifact, observation, choice, context ].each do |record|
      connection = ApplicationRecord.connection
      input = JSON.parse(connection.select_value(<<~SQL))
        SELECT coordinator_search_input(source)::text FROM #{record.class.table_name} AS source
        WHERE #{record.class.primary_key} = #{connection.quote(record.id)}
      SQL
      expect(input).not_to have_key("content_text")
      expect(JSON.generate(input)).not_to include("not a collection input", "unrelated")
      expect(input.fetch(record.class.primary_key)).to eq(record.id)
    end
  end

  it "keeps collection paths and identities stable when only ignored nested fields change" do
    choice = create(:coordinator_read_agent_choice)
    context = create(:coordinator_read_coord_context)
    before_choice = values_for(choice)
    before_context = values_for(context)
    choice.update_columns(alternatives: choice.alternatives.map { _1.merge("option_id" => "changed option") })
    document = context.document.deep_dup
    document.fetch("work_items").first["status"] = "completed"
    context.update_columns(document:)
    expect(values_for(choice)).to eq(before_choice)
    expect(values_for(context)).to eq(before_context)
  end

  it "moves derived ownership and document identity when a source identity changes" do
    choice = create(:coordinator_read_agent_choice)
    old_id = choice.id
    connection = ApplicationRecord.connection
    choice.class.where(choice_id: old_id).update_all(choice_id: "renamed-choice")
    expect(connection.select_value(<<~SQL)).to eq(0)
      SELECT COUNT(*) FROM coordinator_search_values
      WHERE source_table = 'agent_choices' AND source_id = #{connection.quote(old_id)}
    SQL
    rows = values_for(choice.class.find("renamed-choice"))
    expect(rows).not_to be_empty
    expect(rows.map { _1.fetch("document_id") }.uniq).to eq([ "renamed-choice" ])
  end

  it "keeps raw nested field paths while updating Decision leaves and WorkItem identity" do
    decision = create(:coordinator_read_decision_definition)
    definition = decision.definition.deep_dup
    definition.fetch("document").fetch("topic")["aliases"] = [ "new alias", "日本語" ]
    definition.fetch("document").fetch("conditions")["languages"] = [ "ruby", "rust" ]
    decision.update_columns(definition:)
    expect(values_for(decision, field: "decision.topic_aliases").map { _1.fetch("value") }).to eq([ "new alias", "日本語" ])
    expect(values_for(decision, field: "decision.conditions").map { _1.fetch("value") }).to contain_exactly("implementation", "ruby", "rust")

    context = create(:coordinator_read_coord_context)
    before = values_for(context)
    document = context.document.deep_dup
    item = document.fetch("work_items").first
    item["work_item_id"] = "updated-work-item"
    item["goal"] = "Updated goal"
    context.update_columns(document:)
    after = values_for(context)
    expect(after.map { _1.fetch("document_id") }.uniq).to eq([ "updated-work-item" ])
    expect(after.map { _1.fetch("id") }).to eq(before.map { _1.fetch("id") })
    expect(after.map { _1.fetch("value") }).to contain_exactly("Updated goal", "The result is verifiable")
  end

  it "handles partial projections and retains indexes when no searchable values exist yet" do
    artifact = Coordinator::Read::DevelopmentArtifact.create!(artifact_id: SecureRandom.uuid_v7)
    expect(values_for(artifact)).to be_empty
    artifact.update!(labels: [ "now available" ])
    expect(values_for(artifact).map { _1.fetch("value") }).to eq([ "now available" ])
    artifact.update!(labels: [])
    expect(values_for(artifact)).to be_empty
  end

  it "rolls back both source and derived changes together" do
    artifact = create(:coordinator_read_development_artifact, labels: [ "original" ])
    ApplicationRecord.transaction do
      artifact.update!(labels: [ "rolled back" ])
      expect(values_for(artifact).map { _1.fetch("value") }).to eq([ "rolled back" ])
      raise ActiveRecord::Rollback
    end
    expect(artifact.reload.labels).to eq([ "original" ])
    expect(values_for(artifact).map { _1.fetch("value") }).to eq([ "original" ])
  end

  it "removes only the truncated source table's derived rows" do
    artifact = create(:coordinator_read_development_artifact, labels: [ "removed" ])
    choice = create(:coordinator_read_agent_choice)
    ApplicationRecord.connection.execute("TRUNCATE development_artifacts CASCADE")
    expect(values_for(artifact)).to be_empty
    expect(values_for(choice)).not_to be_empty
  end

  it "handles insert_all and delete_all without creating orphan derived observations" do
    observation = create(:coordinator_read_development_artifact_observation, labels: [ "retained label" ])
    attributes = observation.attributes.except("observation_id")
    another_id = SecureRandom.uuid_v7
    Coordinator::Read::DevelopmentArtifactObservation.insert_all!([
      attributes.merge("observation_id" => another_id, "observed_sequence" => observation.observed_sequence + 1)
    ])
    inserted = Coordinator::Read::DevelopmentArtifactObservation.find(another_id)
    expect(values_for(inserted).map { _1.fetch("value") }).to eq([ "retained label" ])
    Coordinator::Read::DevelopmentArtifactObservation.where(observation_id: another_id).delete_all
    expect(values_for(inserted)).to be_empty
    expect(values_for(observation).map { _1.fetch("value") }).to eq([ "retained label" ])
  end

  it "rebuilds missing derived rows idempotently in bounded batches from present read rows" do
    artifacts = create_list(:coordinator_read_development_artifact, 101, labels: [ "backfilled" ])
    ApplicationRecord.connection.execute("DELETE FROM coordinator_search_values")
    backfill = Coordinator::Read::Repositories::SearchValueBackfill.new
    expect(backfill.call).to eq(101)
    expect(values_for(artifacts.first).map { _1.fetch("value") }).to eq([ "backfilled" ])
    expect(values_for(artifacts.last).map { _1.fetch("value") }).to eq([ "backfilled" ])
    before = values_for(artifacts.first)
    expect(backfill.call).to eq(101)
    expect(values_for(artifacts.first)).to eq(before)
    expect(ApplicationRecord.connection.select_value("SELECT COUNT(*) FROM coordinator_search_values")).to eq(101)
  end

  it "has trigram indexes over scalar bodies and raw nested values without B-tree body indexes" do
    definitions = ApplicationRecord.connection.select_values(<<~SQL)
      SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname LIKE 'idx_search_%'
    SQL
    expect(definitions).to include(a_string_including("USING gin (value gin_trgm_ops)"))
    expect(definitions).to include(a_string_including("USING gin (content_text gin_trgm_ops)"))
    expect(definitions).to include(a_string_including("selected ->> 'summary'"))
    expect(definitions.grep(/USING btree.*content_text/)).to be_empty
  end

  it "indexes the native latest-observation order rather than incidental projection sequence" do
    definition = ApplicationRecord.connection.select_value(<<~SQL)
      SELECT indexdef FROM pg_indexes
      WHERE schemaname = 'public' AND indexname = 'idx_search_observations_current'
    SQL
    expect(definition).to include("(artifact_id, observed_global_position DESC NULLS LAST, observation_id DESC)")
  end

  it "waits for a concurrent source writer before backfilling its latest committed text" do
    artifact = create(:coordinator_read_development_artifact, labels: [ "before writer" ])
    locked = Queue.new
    release = Queue.new
    writer = Thread.new do
      ApplicationRecord.connection_pool.with_connection do
        ApplicationRecord.transaction do
          record = Coordinator::Read::DevelopmentArtifact.lock.find(artifact.artifact_id)
          locked << true
          release.pop
          record.update!(labels: [ "after writer" ])
        end
      end
    end
    locked.pop
    backfill = Thread.new { Coordinator::Read::Repositories::SearchValueBackfill.new.call }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      waiting = ApplicationRecord.connection.select_value(<<~SQL)
        SELECT EXISTS (
          SELECT 1 FROM pg_stat_activity
          WHERE datname = current_database() AND pid <> pg_backend_pid()
            AND wait_event_type = 'Lock' AND query LIKE '%LIMIT 100 FOR UPDATE%'
        )
      SQL
      break if waiting
      raise "Backfill did not wait for its source-row lock" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.01
    end
    release << true
    expect(writer.value).to be_truthy
    expect(backfill.value).to eq(1)
    expect(values_for(artifact).map { _1.fetch("value") }).to eq([ "after writer" ])
  ensure
    release << true if release && writer&.alive?
    writer&.join(5)
    backfill&.join(5)
  end
end
