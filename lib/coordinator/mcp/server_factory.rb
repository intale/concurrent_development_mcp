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
        Use development_search to find context without loading whole Skills, Artifact observations,
        Guidance, Choices, Decisions or WorkItem histories. Supply explicit whitelisted fields and
        literal contains/starts_with/ends_with/equals expressions; equals compares one complete value.
        Each AND/OR/NOT tree is evaluated within one raw scalar, never across fields or array members.
        Selected fields combine by OR/union and exact scope/Repository/type filters intersect.
        Values require at least 3 Unicode characters and every Boolean alternative a positive literal
        containing three consecutive alphanumeric characters. NOT only excludes within anchored AND/OR;
        foo OR NOT bar and negative-only searches are rejected. Case sensitivity defaults to true.
        Percent, underscore and backslash are literal text; no regex, SQL, wildcards, linguistic
        matching or client-generated digests/Base64 are accepted. For example, request
        {"fields":[{"field":"skill.instructions","query":{"operator":"and","operands":[
        {"match":"contains","value":"checkpoint"},{"operator":"not","operands":[
        {"match":"contains","value":"obsolete"}]}]}}],"filters":{"scope":"project:example"},"limit":20}.
        Follow each hit's typed retrieval_actions for complete context and its field/path for the
        actual matched scalar. Artifact hits expose both metadata and content actions, with exact
        observation identity when available. Excerpts are passive plain text; binary content is not
        decoded, URLs are not fetched and Resource bodies are not projected or ingested by search.
        Results use owner updated_at descending then stable identity order. Copy the returned opaque
        cursor unchanged for live keyset pagination: updates may move hits between pages and no retained
        snapshot or projection freshness is promised. Every source/field branch and the final union are
        capped; default page 20, maximum 50. Eligible trigram literals and LIMIT do not guarantee constant
        query time or index selection. Any branch budget failure returns no partial page: narrow the query
        and retry. Reduce page size on a response-byte limit. Search is an immediate read, not a mutation Task.
        When asked to migrate a project's development memory, inspect that project with the
        client's own available capabilities and choose sources by their semantic role and the
        user's requested scope, never by a server-prescribed directory layout. The coordinator
        cannot read caller paths, inspect Git, fetch URLs, or execute imported content. Publish
        reusable instructions and passive support assets through skill_publish or
        skill_publish_batch. Capture exact passive plans, decisions, requirements, documentation,
        evidence, profiles, caller-constructed checkpoint metadata, and import audits through
        development_artifact_capture or its Batch companion, then declare typed relationships.
        Each capture allocates a stable UUIDv7 Artifact and a distinct immutable observation. Use
        development_artifact_update with the latest projected stream_revision to change selected
        properties; stale revisions are rejected from authoritative event-store state, while the
        available projection remains readable. Use development_artifact_get with observation_id
        for exact historical classification and content evidence.
        If title, kind, or labels were wrong, use development_artifact_classification_correct with
        the observed classification_revision; it never changes bytes, media type, or provenance.
        Preserve a cited URL without saved response bytes only as an external_reference whose
        exact content is the URL plus one newline. First form a dry-run inventory; use stable
        command and Batch identities for resumption; poll both Tasks and Operation Batches; verify
        projected bytes, digests, assets, relations, outcomes, counts, and exact replay; capture an
        import_manifest last. Do not fabricate live coordination facts from historical material or
        retire local sources before successful verification and explicit user authorization.
        Use skill_list to discover persisted AI Skills and select an exact, case-sensitive name and scope;
        the server does not infer scope precedence. Use skill_get before updating and pass its revision as
        skill_publish expected_revision (zero creates a new tuple). A skill_revision_conflict writes no Skill
        or Command fact; refresh skill_get and retry with a new command when appropriate. Each publication is
        one complete immutable instructions-and-assets snapshot. skill_asset_get returns text for UTF-8 assets
        and canonical Base64 only for binary assets;
        the coordinator never inspects or executes stored assets, so inspect and authorize them externally.
        Skill reads are available projections and may keep serving an older revision while projection catches up.
        After acquiring a WorkItem, declare its complete initial advisory Resource work-intention set before
        editing, and expand that same set before editing any additional Resource. Shared is the default mode;
        choose exclusive only after deciding that overlapping work is incompatible. Shared intentions may
        overlap. Any overlap involving an exclusive intention fails immediately with the existing intentions'
        owners, purpose, context, scope, and expiry; the coordinator never queues, waits, preempts, or promises
        that shared changes will merge cleanly. Expansion never renews expiry. Renew or withdraw the entire exact
        observed intention set; a stale set, intention ID, or fencing token is rejected by authoritative facts.
        A clean or replacement client that knows only an exact project scope uses coordination_list to discover
        available current/recent ChangeSets and follows its complete coord_context actions; this is not Task
        enumeration. Canonical coordination IDs are globally namespaced, while human/local labels may repeat in
        different project scopes. Use decision_list to discover projected policy by Repository UUID and extensible
        topic. decision_resolve currently evaluates registered single-choice topics and returns a typed result for
        strategies whose distinct merge semantics are not implemented.
        After submitting the final Candidate and withdrawing the work-intention set, use work_item_complete to select that
        exact Candidate and finish the active Attempt/WorkItem. Produced artifact/contract labels are attributed
        coordination facts. Dependency and ChangeSet progress then converge through idempotent process commands;
        coord_context may continue serving an older available view while they catch up.
        Accepted interpretations are still non-normative: use decision_activate to establish policy,
        persist its Task handle, and use decision_get only as latest available projected evidence.
        To correct active policy, first accept a correction interpretation, then call decision_correct
        with decision_get's current_head event. A stale projected head is still served and may produce
        a decision_revision_changed conflict; refresh decision_get and submit a new command when appropriate.
        Use decision_resolve for the latest available registered single-choice context of an Attempt. Its digest
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
        Use candidate_submit to checkpoint an attributed commit only after passing the full exact work-intention
        set, intention IDs, Resource IDs, fencing tokens, and a typed change manifest. This records accountability
        for every changed Resource; it does not promise conflict-free integration. The mutation is a durable Task;
        stale or uncovered observations are rejected from authoritative event-store facts. Candidate evidence
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
        After the exact latest composite verification passes, use release_activation_record to record one
        attributed external activation point. The ReleaseSet lifecycle Saga completes activated releases and
        requests compensation after partial integration or composite-verification failure. If compensation is
        requested, external systems perform it and release_compensation_complete records evidence covering every
        exact integrated member. All release mutations remain correlated to physical ReleaseSet preparation.
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
