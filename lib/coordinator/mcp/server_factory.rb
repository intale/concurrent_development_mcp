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
        lifecycle fact has also been observed, and invalidated means an observed Decision change requires
        replanning. After invalidation, resolve current Decisions and record a new Choice ID; do not reuse or
        resurrect the old Choice. Use agent_choice_impact_list with the Attempt ID to inspect paginated
        explicit invalidating and no-effect assessments. Both Choice queries may lag, and no observed status
        is a freshness or write-authorization claim.
        Use candidate_submit to checkpoint an attributed commit only after passing the full exact lease set,
        lease IDs, resource hashes, fencing tokens, and a typed change manifest. The mutation is a durable Task;
        stale or unauthorized observations are rejected from authoritative event-store facts. Candidate evidence
        remains attributed_unverified because the coordinator does not inspect Git or run CI. candidate_get serves
        every currently observed evidence component, candidate_list retains bounded Attempt checkpoint history,
        and coord_context carries only the latest observed checkpoint per Attempt. These available views may lag
        and never authorize a Candidate submission.
        Use candidate_impact_surface_submit to attach one attributed semantic-impact surface to the exact Candidate
        head and source-evidence digests. The mutation is a durable Task and does not claim that an analyzer ran.
        Use candidate_impact_get with an explicit incoming or outgoing direction to inspect bounded, latest available
        potential relationships and its optional latest available Candidate-impact policy summary. Advisory warnings
        recommend external verification without creating a gate. For a gating summary, use
        verification_obligations_list with at least one filter to inspect latest available coordination requirements,
        evidence progress, and attributed outcomes. It defaults to open; request satisfied or failed explicitly.
        Empty or older content may reflect projection lag and is never merge authorization. Path and semantic matches are
        evidence, not incompatibility or merge authorization. Use verification_obligation_claim to acquire temporary
        exclusive coordination before performing an obligation externally. Persist its Task handle and, after
        completion, retain the returned claim ID and fencing token. A claim does not mean work started or succeeded.
        Use compatibility_assessment_submit with that exact claim ID/fencing token and the obligation's immutable
        candidate heads and validity digest. Persist the returned Task handle. Each accepted assessment records exact
        producer, run, input, result, finding, and timestamp attribution; it may leave the obligation open or immediately
        satisfy/fail it. Stale projected context, claim fences, candidate bindings, or policy are authoritatively denied.
        A user may explicitly waive an exact current open or failed obligation with verification_obligation_waive;
        the actor label is attribution rather than authentication, and waiver never means verification passed.
        Use merge_snapshot_register to bind an external producer's exact ordered Candidate composition to one
        repository target/base and merge commit. The durable Task rechecks immutable Candidate and manifest facts
        directly in the event store and rejects mismatches or reused identities atomically. Registration remains
        attributed_unverified: the coordinator does not inspect Git or prove that the composition exists.
        merge_snapshot_get serves the latest available projection and may temporarily report not observed.
        Use merge_verification_submit with the exact complete binding returned by merge_snapshot_register or
        merge_snapshot_get. It accepts only attributed combined-test evidence. Failed, inconclusive, and
        not-applicable assessments remain durable facts and may be followed by a new assessment; an exact pass
        without error or critical findings verifies that immutable snapshot in the same authoritative command.
        The projected verification history may lag and never authorizes the command.
        Use merge_authorization_request only after observing the exact registered and verified snapshot evidence.
        Include an attributed fresh target-base observation and the exact current Candidate-impact policy context,
        or null when no policy is active. The durable Task recomputes all merge-gating obligations directly from
        authoritative event facts. Both grants and structured denials are durable decisions; retry with a new
        command only after correcting the denied evidence. Projected state may lag and is never authorization.
        After an external system completes the exact authorized transition, use merge_observation_record with
        the grant event/digest and exact target before/after OIDs. The durable Task re-evaluates grant currentness
        from authoritative events and rejects changed policy or obligation evidence. A recorded observation is
        caller-attributed and unverified; the coordinator did not perform the merge or inspect Git.
        Use release_set_prepare to freeze 2..16 uniquely identified repositories into one semantic
        integration order after exact snapshot grants are current. The durable Task re-evaluates every
        authorization from authoritative events in one transaction. release_set_get serves the latest
        available projection and may lag without becoming unavailable or authorizing later commands.
        Use release_repository_integration_record in the frozen member order. A success must bind the
        member's exact MergeObserved fact; a bounded attributed failure remains retryable until any prior
        successful integration makes compensation necessary. After every member succeeds, use
        release_verification_record with the exact ordered integration event references and attributed
        composite evidence. These durable Tasks recheck ReleaseSet history without consulting projections.
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
