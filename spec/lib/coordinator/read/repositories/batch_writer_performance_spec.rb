# frozen_string_literal: true

RSpec.describe "Selective batch persistence measurements", :read_model do
  it "compares a thousand individual updates with a single compatible patch statement" do
    model = Coordinator::Read::Repository
    time = Time.now.utc
    attributes = Array.new(1000) { attributes_for(:coordinator_read_repository).merge(created_at: time, updated_at: time) }
    model.insert_all!(attributes, record_timestamps: false)
    ids = attributes.map { _1.fetch(:repository_id) }
    baseline = ProjectionBatchMeasurement.call(model) do
      ids.each_with_index { |id, index| model.where(repository_id: id).update_all(display_name: "individual-#{index}") }
    end
    patches = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :repository_id ])
    batched = ProjectionBatchMeasurement.call(model) do
      ids.each_with_index { |id, index| patches.assign(repository_id: id, display_name: "batched-#{index}") }
      Coordinator::Read::Repositories::BatchWriter.new(model:, patches:).call
    end
    expect(baseline.fetch(:statement_count)).to eq(1000)
    expect(batched.fetch(:statement_count)).to eq(1)
    expect(model.where("display_name LIKE ?", "batched-%").count).to eq(1000)
    [ baseline, batched ].each do |measurement|
      expect(measurement.fetch(:sql_duration_ms)).to be >= 0
      expect(measurement.fetch(:allocated_objects)).to be > 0
      expect(measurement.fetch(:cluster_wal_upper_bound_bytes)).to be >= 0
    end
    if ENV["COORDINATOR_BENCHMARK_REPORT"] == "1"
      plans = { individual_statement: ProjectionBatchMeasurement.explain(model, baseline.fetch(:statements).first),
        batched_statement: ProjectionBatchMeasurement.explain(model, batched.fetch(:statements).sole) }
      puts JSON.generate(workload: "1000 repository name patches", baseline: baseline.except(:statements),
        batched: batched.except(:statements), repeated_statement_explain: plans)
    end
  end
end
