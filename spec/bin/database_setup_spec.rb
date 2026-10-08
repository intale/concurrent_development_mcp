# frozen_string_literal: true

RSpec.describe "database setup executables" do
  it "provisions the accepted development store and ordinary test store through public tasks" do
    contents = Rails.root.join("bin/setup_db").read

    expect(contents).to include(
      'PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/eventstore_migration_target_v7" bundle exec rake pg_eventstore:create',
      'PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/eventstore_migration_target_v7" bundle exec rake pg_eventstore:migrate',
      'PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/eventstore_test" bundle exec rake pg_eventstore:create',
      'PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/eventstore_test" bundle exec rake pg_eventstore:migrate'
    )
    expect(contents).not_to include('localhost:5532/eventstore"', 'localhost:5532/eventstore_migration_target"', "eventstore_migration_target_test")
  end

  it "provisions one isolated ordinary event store per parallel runner" do
    contents = Rails.root.join("bin/setup_parallel_tests").read

    expect(contents).to include('PARALLEL_TEST_PROCESSORS:-15', 'eventstore${parallel_test_worker}_test')
    expect(contents).not_to include("migration_target_test")
  end
end
