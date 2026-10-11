# frozen_string_literal: true

module Coordinator::Shared
  module Observability
    # Rails glue lives outside the isolated, runtime-RBS-covered core.
    class SqlNotifications
      def initialize(session:)
        @session = session
        @invocation = SqlInvocation.new(session:)
        @active = false
      end

      def start
        return if @subscriber

        @subscriber = ActiveSupport::Notifications.monotonic_subscribe("sql.active_record") do |_name, started_at, finished_at, _id, payload|
          Runtime.safely(:sql_notification) { capture(started_at, finished_at, payload) }
        end
        @active = true
        nil
      end

      def stop
        @active = false
        ActiveSupport::Notifications.unsubscribe(@subscriber) if @subscriber
        @subscriber = nil
        nil
      end

      private

      def capture(started_at, finished_at, payload)
        return unless @active && @session.pid == Process.pid
        return if payload[:cached] || payload[:name] == "SCHEMA"

        error = payload[:exception_object]
        exception_type = error&.class&.name || (payload[:exception] ? "Exception" : nil)
        @invocation.call(sql: payload.fetch(:sql), started_at:, finished_at:, exception_type:)
        nil
      end
    end
  end
end
