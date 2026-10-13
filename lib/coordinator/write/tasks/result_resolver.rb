# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class ResultResolver
      def initialize(event_store:,
        command_loader: CommandLifecycle::Loader.new(event_store:),
        source_loader: CommandResults::SourceLoader.new(event_store:),
        assembler: CommandResults::Assembler.new(event_store:))
        @command_loader = command_loader
        @source_loader = source_loader
        @assembler = assembler
      end

      def call(state)
        snapshot = @command_loader.call(state.command_id)
        unless snapshot.state.terminal? && snapshot.state.tool_name == state.tool_name
          raise InvalidCommandHistory, "Completed Task has no matching terminal command"
        end

        source = @source_loader.call(snapshot.persisted_events.last)
        raise InvalidCommandHistory, "Completed Task has no authoritative instruction" unless source

        @assembler.call(source).semantic_result
      end
    end
  end
end
