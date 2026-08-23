# frozen_string_literal: true

module Coordinator
  module Mcp
    class ServerFactory
      CAPABILITIES = {
        tools: { listChanged: true },
        prompts: { listChanged: true },
        resources: { listChanged: true },
        logging: {},
        extensions: Tasks::Capability::EXTENSIONS
      }.freeze

      INSTRUCTIONS = <<~TEXT.freeze
        Coordinate checkpointed concurrent development across repositories.
        Actor fields are attribution labels, not authenticated identities.
        Every application request requires the io.modelcontextprotocol/tasks capability.
        Mutations return durable Task handles: persist each taskId, poll tasks/get at
        pollIntervalMs, and use tasks/cancel for cooperative cancellation. Reuse command_id
        after an unknown mutation result. Read tools return the latest available projection,
        which may be stale; command decisions recheck authoritative event-store facts.
        After acquiring a WorkItem, reserve its complete initial file write set before editing,
        and expand that same set before editing any additional file. Expansion never renews expiry.
        Renew the entire exact observed lease set before its deadline when more work time is needed;
        a stale set, lease ID, or fencing token is safely rejected by authoritative event facts.
        Release the entire exact observed lease set when editing is finished; partial release is not available.
        Accepted interpretations are still non-normative: use decision_activate to establish policy,
        persist its Task handle, and use decision_get only as latest available projected evidence.
        To correct active policy, first accept a correction interpretation, then call decision_correct
        with decision_get's current_head event. A stale projected head is still served and may produce
        a decision_revision_changed conflict; refresh decision_get and submit a new command when appropriate.
        Use decision_resolve for the latest available testing-framework context of an Attempt. Its digest
        and partition evidence may lag and are context for a later authoritative command, never authority alone.
        Before committing to a significant testing-framework selection, call decision_resolve and pass its
        exact decision_context to agent_choice_record. A stale_context result means no choice was recorded;
        refresh decision_resolve and submit a new command. A confirmation_required result has no bypass in
        this protocol version and must be escalated instead of silently accepted. Use agent_choice_get for
        the latest available evidence: recorded means that fact has been observed, accepted means the next
        lifecycle fact has also been observed, and neither status is a freshness or write-authorization claim.
        The coordinator records attributed evidence and does not execute Git, CI, or agent work.
      TEXT

      def initialize(tasks_extension:)
        @tasks_extension = tasks_extension
      end

      def call
        server = Tasks::Server.new(
          name: "concurrent-development-coordinator",
          title: "Concurrent Development Coordinator",
          version: "0.1.0",
          instructions: INSTRUCTIONS,
          tools: ToolRegistry.all,
          capabilities: CAPABILITIES,
          configuration: ::MCP::Configuration.new(
            exception_reporter: method(:report_exception),
            validate_tool_call_arguments: true,
            validate_tool_call_results: true
          ),
          server_context: {}
        )
        @tasks_extension.register(server)
      end

      private

      def report_exception(error, _server_context)
        Rails.error.report(error, handled: true)
      end
    end
  end
end
