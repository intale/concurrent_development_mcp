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
    expect(backfill.call).to eq(101)
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
