# frozen_string_literal: true

module Coordinator::Mcp
  module ObservabilityMethods
    NAMES = %w[
      initialize ping server/discover subscriptions/listen
      tools/list tools/call prompts/list prompts/get completion/complete
      resources/list resources/read resources/templates/list resources/subscribe resources/unsubscribe
      logging/setLevel notifications/initialized notifications/progress notifications/roots/list_changed
      notifications/cancelled notifications/elicitation/complete
      tasks/get tasks/update tasks/cancel
    ].freeze
  end
end
