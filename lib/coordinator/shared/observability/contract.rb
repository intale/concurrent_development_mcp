# frozen_string_literal: true

module Coordinator::Shared
  module Observability
    module Contract
      OUTCOMES = %w[
        ok accepted denied invalid not_found not_modified command_id_reused
        conflict busy limit_reached pending cancelled error unknown
      ].freeze
      SQL_OPERATIONS = %w[SELECT INSERT UPDATE DELETE BEGIN COMMIT ROLLBACK SAVEPOINT RELEASE OTHER].freeze
      DURATION_BOUNDARIES = [ 0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0, 60.0 ].freeze
      AGE_BOUNDARIES = [ 0.1, 1.0, 5.0, 10.0, 30.0, 60.0, 300.0, 900.0, 3600.0 ].freeze
      MCP_DIMENSIONS = %w[rpc.method mcp.tool.name].freeze
      SUBSCRIPTION_DIMENSIONS = %w[subscription.set subscription.name event.type].freeze
      SQL_DIMENSIONS = %w[db.operation.name].freeze

      module_function

      def metrics
        @metrics ||= [
          definition(:mcp_started, :counter, "{call}", MCP_DIMENSIONS, "MCP invocations entered"),
          definition(:mcp_completed, :counter, "{call}", MCP_DIMENSIONS + [ "outcome" ], "MCP invocations completed"),
          definition(:mcp_duration, :histogram, "s", MCP_DIMENSIONS + [ "outcome" ], "MCP invocation runtime", DURATION_BOUNDARIES),
          definition(:mcp_in_flight, :up_down_counter, "{call}", MCP_DIMENSIONS, "MCP invocations currently executing"),
          definition(:subscription_started, :counter, "{call}", SUBSCRIPTION_DIMENSIONS, "Subscription handler invocations entered"),
          definition(:subscription_completed, :counter, "{call}", SUBSCRIPTION_DIMENSIONS + [ "outcome" ], "Subscription handler invocations completed"),
          definition(:subscription_delivered, :counter, "{event}", SUBSCRIPTION_DIMENSIONS, "Events delivered to handlers, including native retries"),
          definition(:subscription_duration, :histogram, "s", SUBSCRIPTION_DIMENSIONS + [ "outcome" ], "Subscription handler runtime", DURATION_BOUNDARIES),
          definition(:subscription_in_flight, :up_down_counter, "{call}", SUBSCRIPTION_DIMENSIONS, "Subscription handlers currently executing"),
          definition(:subscription_oldest_in_flight, :observable_gauge, "s", SUBSCRIPTION_DIMENSIONS, "Age of the oldest unfinished handler invocation"),
          definition(:subscription_delivery_age, :histogram, "s", SUBSCRIPTION_DIMENSIONS, "Event creation to handler entry, including intentional replay", AGE_BOUNDARIES),
          definition(:sql_completed, :counter, "{query}", SQL_DIMENSIONS + [ "outcome" ], "Executed Rails SQL queries, excluding cache hits and schema housekeeping"),
          definition(:sql_duration, :histogram, "s", SQL_DIMENSIONS + [ "outcome" ], "Actual Rails SQL execution duration", DURATION_BOUNDARIES)
        ].freeze
      end

      def outcome(value)
        OUTCOMES.include?(value) ? value : "unknown"
      end

      def definition(key, kind, unit, dimensions, description, boundaries = [])
        MetricDefinition.new(
          key:, name: "coordinator.#{key.to_s.tr('_', '.')}", kind:, unit:,
          dimensions:, description:, boundaries:
        )
      end
      private_class_method :definition
    end
  end
end
