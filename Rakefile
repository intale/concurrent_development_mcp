# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative "config/application"

if ARGV.any? { |task_name| task_name.match?(/\Apg_eventstore:/) }
  load 'pg_eventstore/tasks/setup.rake'
end

Rails.application.load_tasks
