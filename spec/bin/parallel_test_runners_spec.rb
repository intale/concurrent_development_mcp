# frozen_string_literal: true

require "open3"

RSpec.describe "parallel test executables" do
  RUNNERS = {
    "bin/parallel-rspec" => "tmp/parallel_runtime_rspec_rbs.log",
    "bin/parallel-rspec-plain" => "tmp/parallel_runtime_rspec_plain.log",
    "bin/parallel-cucumber" => "tmp/parallel_runtime_cucumber.log"
  }.freeze

  it "loads the real parallel_tests CLI from every executable" do
    RUNNERS.each_key do |relative_path|
      stdout, stderr, status = Open3.capture3(
        { "PARALLEL_TEST_PROCESSORS" => "1" },
        Rails.root.join(relative_path).to_s,
        "--help"
      )

      expect(status).to be_success, "#{relative_path}: #{stderr}"
      expect(stdout).to include("How many processes to use")
    end
  end

  it "defaults every runner to ten workers and rejects invalid counts before execution" do
    RUNNERS.each_key do |relative_path|
      contents = Rails.root.join(relative_path).read
      expect(contents).to include('PARALLEL_TEST_PROCESSORS:-10')

      _stdout, stderr, status = Open3.capture3(
        { "PARALLEL_TEST_PROCESSORS" => "0" },
        Rails.root.join(relative_path).to_s,
        "--help"
      )
      expect(status.exitstatus).to eq(64)
      expect(stderr).to include("PARALLEL_TEST_PROCESSORS must be a positive integer")
    end
  end

  it "assigns one exclusive smart-runtime file to each suite" do
    all_logs = RUNNERS.values

    RUNNERS.each do |relative_path, own_log|
      contents = Rails.root.join(relative_path).read
      expect(contents).to include(own_log)
      expect(contents).not_to include(*(all_logs - [ own_log ]))
      expect(contents).to include('--runtime-log "$')
    end
  end

  it "keeps the typed and plain RSpec worker executables distinct" do
    typed = Rails.root.join("bin/parallel-rspec").read
    plain = Rails.root.join("bin/parallel-rspec-plain").read

    expect(typed).to include("export PARALLEL_TESTS_EXECUTABLE=bin/rspec")
    expect(plain).to include('export PARALLEL_TESTS_EXECUTABLE="bundle exec rspec"')
    expect(plain).to include("unset RBS_TEST_TARGET RBS_TEST_LOGLEVEL RBS_TEST_OPT")
  end

  it "uses a quiet strict Cucumber profile that excludes future scenarios" do
    cucumber_config = Rails.root.join("config/cucumber.yml").read

    expect(cucumber_config).to include(
      %q(parallel_opts = "--format progress --publish-quiet --strict --tags 'not @wip'")
    )
  end

  it "provides one neutral database setup for all three runners" do
    setup = Rails.root.join("bin/setup_parallel_tests").read

    expect(setup).to include('PARALLEL_TEST_PROCESSORS:-10')
    expect(setup).to include('parallel:create[$parallel_test_processes]')
    expect(setup).to include('parallel:migrate[$parallel_test_processes]')
    expect(setup).to include('eventstore${parallel_test_worker}_test')
  end
end
