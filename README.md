# README

## Development

Steps to setup development environment:

- start docker compose first via `docker compose up`
- run `./bin/setup_db` to create rails and pg_eventstore databases if this is your initial run
- run `rails s` to start rails server
- run
  `bundle exec pg-eventstore subscriptions start -r ./config/environment.rb -r ./config/pg_eventstore_subscriptions.rb`
  to start pg_eventstore subscriptions

## Runtime-RBS test gate

Run the logical suite first:

```sh
bundle exec rspec
```

Prepare ten isolated Rails and pg_eventstore database pairs, then run only the
runtime-RBS suite in parallel:

```sh
bin/setup_parallel_rbs
bin/parallel-rspec
```

The parallel workers use explicit numbers 1 through 10. Worker `N` owns
`concurrent_development_mcp<N>_test` and `eventstore<N>_test`; sequential tests
continue to use the unnumbered test databases.

Set the same positive process count for setup and execution to override the
default:

```sh
PARALLEL_TEST_PROCESSORS=4 bin/setup_parallel_rbs
PARALLEL_TEST_PROCESSORS=4 bin/parallel-rspec
```

Paths and `parallel_tests`/RSpec options may be passed to `bin/parallel-rspec`.
Every worker delegates its file group to `bin/rspec`, preserving the complete
repository RBS target.
