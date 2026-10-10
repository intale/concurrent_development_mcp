# frozen_string_literal: true

RSpec.describe "Development search execution boundaries", read_model: true do
  let(:codec) { Coordinator::Read::Search::CursorCodec.new(secret: "search-execution-cursor-integrity") }
  let(:builder) { Coordinator::Read::Search::QueryBuilder.new(cursor_codec: codec) }
  let(:repository) { Coordinator::Read::Repositories::DevelopmentSearch.new(cursor_codec: codec) }

  def query(*selectors)
    builder.call(fields: selectors.map { { field: _1, query: { match: "contains", value: "needle" } } }).value!
  end

  def hold_table(table, locked, release)
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        connection.transaction do
          connection.execute("LOCK TABLE #{table} IN ACCESS EXCLUSIVE MODE")
          locked << true
          release.pop
        end
      end
    end
  end

  def wait_for_blocked_search
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.8
    loop do
      blocked = ApplicationRecord.connection.select_value(<<~SQL)
        SELECT EXISTS (SELECT 1 FROM pg_stat_activity
          WHERE datname = current_database() AND pid <> pg_backend_pid()
            AND wait_event_type = 'Lock'
            AND query LIKE 'SELECT entity_type, document_id, updated_at, source_priority,%')
      SQL
      return if blocked
      raise "Search did not reach its real table lock" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.01
    end
  end

  it "fails the whole page when a later real branch times out, and its next request can succeed" do
    create(:coordinator_read_user_utterance, text: "needle already matched")
    record = create(:coordinator_read_skill)
    create(:coordinator_read_skill_revision, skill: record, instructions: "needle blocked")
    locked = Queue.new
    release = Queue.new
    holder = hold_table("skills", locked, release)
    locked.pop
    result = repository.page(query("guidance.text", "skill.instructions"))
    expect(result).to be_failure
    expect(result.failure.code).to eq("search_budget_exceeded")
    release << true
    holder.value
    expect(repository.page(query("guidance.text", "skill.instructions")).value!.items.length).to eq(2)
  ensure
    release << true if release && holder&.alive?
    holder&.join(5)
  end

  it "keeps one projected repeatable-read snapshot across independently capped field branches" do
    guidance = create(:coordinator_read_user_utterance, text: "needle before update", updated_at: Time.utc(2026, 10, 10, 8))
    create(:coordinator_read_resource, normalized_path: "needle.rb")
    locked = Queue.new
    release = Queue.new
    holder = hold_table("resources", locked, release)
    locked.pop
    request = query("guidance.text", "resource.path")
    reader = Thread.new { repository.page(request) }
    wait_for_blocked_search
    guidance.update!(text: "needle after update", updated_at: Time.utc(2026, 10, 10, 9))
    release << true
    holder.value
    page = reader.value.value!
    matched = page.items.find { _1.entity_type == "guidance" }
    expect(matched.matches.first.excerpt).to eq("needle before update")
    expect(matched.updated_at).to eq("2026-10-10T08:00:00.000000Z")
    expect(repository.page(request).value!.items.find { _1.entity_type == "guidance" }.matches.first.excerpt).to eq("needle after update")
  ensure
    release << true if release && holder&.alive?
    holder&.join(5)
    reader&.join(5)
  end
end
