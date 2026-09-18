# frozen_string_literal: true

RSpec.describe "database setup executable" do
  it "provisions distinct development source and migration-target stores through public tasks" do
    contents = Rails.root.join("bin/setup_db").read

    expect(contents).to include(
      'PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/eventstore" bundle exec rake pg_eventstore:create',
      'PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/eventstore" bundle exec rake pg_eventstore:migrate',
      'PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/eventstore_migration_target" bundle exec rake pg_eventstore:create',
      'PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/eventstore_migration_target" bundle exec rake pg_eventstore:migrate'
    )
  end
end
