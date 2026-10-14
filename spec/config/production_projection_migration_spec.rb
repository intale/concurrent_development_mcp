# frozen_string_literal: true

RSpec.describe "temporary production projection migration" do
  let(:script) { Rails.root.join("bin/migrate-production") }

  it "offers help without accessing Docker or a production environment file" do
    output, error, status = Open3.capture3({ "PRODUCTION_ENV_FILE" => "/missing-production-env" }, script.to_s, "--help")

    expect(status.success?).to be(true)
    expect(error).to be_empty
    expect(output).to include("run|status", "Deploy with bin/deploy-production first", "never recreates databases")
  end

  it "rejects an unreadable environment file before invoking Compose" do
    _, error, status = Open3.capture3({ "PRODUCTION_ENV_FILE" => "/missing-production-env" }, script.to_s)

    expect(status.exitstatus).to eq(64)
    expect(error).to include("readable", "from config/production.env.example first")
  end

  it "rejects unsafe project names before creating a lock or invoking Compose" do
    environment = { "PRODUCTION_ENV_FILE" => "/dev/null", "PRODUCTION_COMPOSE_PROJECT" => "../unsafe-project" }
    _, error, status = Open3.capture3(environment, script.to_s)

    expect(status.exitstatus).to eq(64)
    expect(error).to include("valid lowercase Compose project name")
  end

  it "rejects unsupported actions before accessing production configuration" do
    _, error, status = Open3.capture3({}, script.to_s, "reset")

    expect(status.exitstatus).to eq(64)
    expect(error).to include("run|status")
  end

  it "has valid Bash syntax and executable permissions" do
    _, _, status = Open3.capture3("bash", "-n", script.to_s)

    expect(status.success?).to be(true)
    expect(File.executable?(script)).to be(true)
  end

  it "uses explicit production opt-in and public CLI lifecycle without resetting ordinary consumers" do
    text = File.read(script)

    expect(text).to include("COORDINATOR_ALLOW_PROJECTION_MIGRATION=1", "pg-eventstore subscriptions start",
      "docker stop --time 60", "subscription_positions_from_db", "max_count: 1")
    expect(text).not_to include("db:prepare", "db:setup", "reset_position", "force_lock", "drop_database")
  end

  it "has valid embedded Ruby and requires all three schema changes" do
    text = File.read(script).split("<<'RUBY' || true\n", 2).last.split("\nRUBY\n", 2).first

    expect { RubyVM::InstructionSequence.compile(text) }.not_to raise_error
    expect(text).to include("20261014125000", "20261014131800", "20261014134600", "max_subscription_position")
  end

  it "keeps both existing production entry points guarded unless the operator opts in" do
    %w[pg_eventstore_projection_initialization.rb pg_eventstore_projection_numbers_replay.rb].each do |name|
      text = File.read(Rails.root.join("config", name))

      expect(text).to include('Rails.env.production? && ENV["COORDINATOR_ALLOW_PROJECTION_MIGRATION"] != "1"',
        "abort(", "Use bin/migrate-production")
    end
  end
end
