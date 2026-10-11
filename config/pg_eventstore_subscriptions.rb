# frozen_string_literal: true

ENV['COORDINATOR_OBSERVABILITY_ROLE'] = 'subscriptions'

Coordinator::Container["subscription_sets.process_managers"].start
Coordinator::Container["subscription_sets.task_results"].start
Coordinator::Container["subscription_sets.read_models"].start
