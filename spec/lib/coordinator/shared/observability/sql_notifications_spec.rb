# frozen_string_literal: true

RSpec.describe Coordinator::Shared::Observability::SqlNotifications, observability: true do
  let(:runtime) { Coordinator::Shared::Observability::Runtime }
  let(:connection) { ActiveRecord::Base.connection }

  def sql_spans
    telemetry_spans.select { _1.name.start_with?("SQL ") }
  end

  it "records actual query timing under the active invocation and strips literal values" do
    session = runtime.current
    parent = session.tracer.start_span("parent")
    token = OpenTelemetry::Context.attach(OpenTelemetry::Trace.context_with_span(parent))
    started = Time.now.to_f
    result = connection.select_value("SELECT 'private-query-value' FROM pg_sleep(0.025)")
    finished = Time.now.to_f
    OpenTelemetry::Context.detach(token)
    parent.finish

    expect(result).to eq("private-query-value")
    span = sql_spans.fetch(0)
    expect(sql_spans.length).to eq(1)
    expect(span.kind).to eq(:client)
    expect(span.parent_span_id).to eq(parent.context.span_id)
    expect(span.attributes).to include("db.system.name" => "postgresql", "db.operation.name" => "SELECT", "outcome" => "ok")
    expect(span.attributes.fetch("db.query.text")).not_to include("private-query-value", "0.025")
    expect(span.start_timestamp / 1e9).to be_between(started - 0.01, finished)
    expect(span.end_timestamp / 1e9).to be_between(started, finished + 0.01)
    expect((span.end_timestamp - span.start_timestamp) / 1e9).to be >= 0.02
    points = telemetry_metrics.find { _1.name == "coordinator.sql.duration" }.data_points
    expect(points.first.sum).to be >= 0.02
    expect(points.first.attributes).to eq("db.operation.name" => "SELECT", "outcome" => "ok")
  ensure
    OpenTelemetry::Context.detach(token) if token && OpenTelemetry::Trace.current_span.context.valid?
  end

  it "preserves real SQL errors without exporting the database message or bind values" do
    expect { connection.execute("SELECT 'private-error-value'::integer") }.to raise_error(ActiveRecord::StatementInvalid)
    expect(sql_spans.last.attributes).to include("outcome" => "error")
    expect(sql_spans.last.attributes.to_s).not_to include("private-error-value")
    expect(Array(sql_spans.last.events)).to be_empty
    expect(sql_spans.last.status.ok?).to be(false)
  end

  it "uses factory read fixtures and counts only physical execution, not schema or query-cache hits" do
    runtime.shutdown
    repository = FactoryBot.create(:coordinator_read_repository)
    start_test_observability
    repository.class.cache do
      2.times { expect(repository.class.where(repository_id: repository.repository_id).pluck(:repository_id)).to eq([ repository.repository_id ]) }
    end
    expect(sql_spans.length).to eq(1)
    expect(telemetry_metrics.find { _1.name == "coordinator.sql.completed" }.data_points.first.value).to eq(1)
  end

  it "does not export bound values from a real read-model query" do
    runtime.shutdown
    repository = FactoryBot.create(:coordinator_read_repository, display_name: "private-bound-value")
    start_test_observability
    expect(repository.class.where(display_name: "private-bound-value").pluck(:repository_id)).to eq([ repository.repository_id ])
    expect(sql_spans.last.attributes.fetch("db.query.text")).to include("WHERE")
    expect(sql_spans.last.attributes.to_s).not_to include("private-bound-value", repository.repository_id)
  end

  it "retains more than the old 512-character span limit without leaking literals" do
    sql = "SELECT 1 AS value WHERE 1 IN (#{([ '1' ] * 400).join(',')}) AND 'private-long-value' = 'private-long-value'"
    expect(connection.select_value(sql)).to eq(1)
    text = sql_spans.last.attributes.fetch("db.query.text")
    expect(text.length).to be > 512
    expect(text.length).to be <= 2048
    expect(text).not_to include("private-long-value")
  end

  it "does not trace direct event-store queries", :event_store do
    runtime.current.span_exporter.reset
    PgEventstore.client.read(PgEventstore::Stream.all_stream,
      options: { max_count: 1, filter: { event_types: [ { type: "RepositoryRegistered" } ] } })
    expect(sql_spans).to be_empty
  end

  it "omits unsafe SQL text without omitting timing or altering the result" do
    expect(connection.select_value("SELECT $tag$private-first\nprivate-second$tag$")).to eq("private-first\nprivate-second")
    expect(sql_spans.last.attributes).not_to have_key("db.query.text")
    expect(sql_spans.last.attributes).to include("db.operation.name" => "SELECT", "outcome" => "ok")
  end

  it "unsubscribes on shutdown and does not duplicate capture after configuration reuse or restart" do
    start_test_observability
    connection.select_value("SELECT 1")
    expect(sql_spans.length).to eq(1)
    stopped = runtime.current
    runtime.shutdown
    connection.select_value("SELECT 2")
    stopped.metric_reader.reset
    stopped.metric_reader.pull
    counter = stopped.metric_reader.metric_snapshots.find { _1.name == "coordinator.sql.completed" }
    expect(counter.data_points.first.value).to eq(1)
    start_test_observability
    connection.select_value("SELECT 3")
    expect(sql_spans.length).to eq(1)
  end

  it "detaches inherited callbacks and captures SQL exactly once in a forked child" do
    parent = runtime.current
    connection.select_value("SELECT 1")
    ActiveRecord::Base.connection_handler.clear_all_connections!
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      runtime.after_fork
      ActiveRecord::Base.connection.select_value("SELECT 2")
      writer.write(JSON.generate(spans: sql_spans.count, instance_id: runtime.current.instance_id))
      writer.close
      runtime.shutdown
      exit! 0
    end
    writer.close
    data = JSON.parse(reader.read)
    reader.close
    Process.wait(pid)
    expect(data.fetch("spans")).to eq(1)
    expect(data.fetch("instance_id")).not_to eq(parent.instance_id)
    expect(sql_spans.length).to eq(1)
    expect(runtime.current).to equal(parent)
  end
end
