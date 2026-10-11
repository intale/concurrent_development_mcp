# frozen_string_literal: true

module Coordinator::Shared
  module Observability
    class Inventory
      attr_reader :tool_names, :rpc_method_names, :subscription_definitions

      def initialize(tool_names:, rpc_method_names:, subscription_definitions:)
        @tool_names = tool_names.uniq.sort.freeze
        @rpc_method_names = rpc_method_names.uniq.sort.freeze
        @subscription_definitions = subscription_definitions.freeze
        @subscriptions = subscription_definitions.to_h { |definition| [ definition.identity, definition ] }.freeze
      end

      def mcp_attributes(method:, tool_name: nil)
        {
          "rpc.method" => rpc_method_names.include?(method) ? method : "unknown",
          "mcp.tool.name" => method == "tools/call" ? bounded_tool_name(tool_name) : "none"
        }.freeze
      end

      def subscription_attributes(definition:, event_type:)
        registered = @subscriptions[definition.identity]
        return unknown_subscription_attributes unless registered

        {
          "subscription.set" => registered.set_name,
          "subscription.name" => registered.subscription_name,
          "event.type" => registered.event_types.include?(event_type) ? event_type : "unknown"
        }.freeze
      end

      private

      def bounded_tool_name(name)
        tool_names.include?(name) ? name : "unknown"
      end

      def unknown_subscription_attributes
        { "subscription.set" => "unknown", "subscription.name" => "unknown", "event.type" => "unknown" }.freeze
      end
    end
  end
end
