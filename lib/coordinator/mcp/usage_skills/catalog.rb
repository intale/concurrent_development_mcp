# frozen_string_literal: true

module Coordinator::Mcp
  module UsageSkills
    # Documentation is shipped application content, independent of both databases.
    class Catalog
      SCOPE = "mcp:concurrent-development-coordinator"
      RELEASE = 2
      ENTRY_SKILL = "coordinator-getting-started"
      FUNCTION_DESCRIPTIONS = ToolRegistry.all.to_h { [ _1.tool_name, _1.description ] }.freeze

      def self.build(name:, description:, tools:, instructions:)
        rows = tools.map { |tool| "| #{tool} | #{FUNCTION_DESCRIPTIONS.fetch(tool).gsub('|', '\\|').gsub(/\s+/, ' ')} |" }
        reference = [ "| Function | Purpose and outcome |", "| --- | --- |", *rows ].join("\n")
        Definition.new(
          name:, description:, tools:,
          instructions: "# #{name.delete_prefix('coordinator-').tr('-', ' ')}\n\n#{description}\n\n## Function reference\n\n#{reference}\n\n#{instructions}"
        )
      end

      DEFINITIONS = [
        build(
          name: ENTRY_SKILL,
          description: "Discover every server capability: repositories, work plans, resource intentions, checkpoints, Skills/assets, artifacts, search, decisions, verification, merges and releases. Understand asynchronous outcomes, cancellation and recovery.",
          tools: %w[task_get task_cancel],
          instructions: <<~MD
            ## Complete capability map

            Call skill_list with no arguments to discover these static server-provided guides. Every entry identifies source: server and lists its public tools. Retrieve instructions with skill_get using its exact name and scope mcp:concurrent-development-coordinator.

            | Capability | Guide |
            | --- | --- |
            | Repository/resource discovery, dependency plans, WorkItems, Attempts, shared/exclusive intentions, checkpoints and resumable context | coordinator-development-coordination |
            | Stored Skill entities/assets, documents/evidence, linked artifact navigation and bounded imports | coordinator-knowledge-management |
            | Literal and Boolean search over projected development knowledge | coordinator-development-search |
            | User guidance, interpretations, active/corrected policy, agent Choices and invalidation | coordinator-decisions-and-guidance |
            | Candidate compatibility, verification obligations, merge authorization/evidence and multi-repository releases | coordinator-integration-and-release |
            | Asynchronous request outcomes, exact replay and cancellation | coordinator-getting-started |

            These guides ship with the running application. They need no database records, subscription workers, publication, installation script or local files. Load only the guide needed for the task. An agent chooses how to use the returned instructions.

            Project Skills are separate stored knowledge entities. List them with an explicit exact scope, such as project:example, or source: stored to discover entities across scopes. The product scope normally selects built-in documentation. Equal names in different scopes are separate entities. No scope hierarchy or precedence is inferred.

            ## Durable asynchronous requests

            Every domain mutation returns a durable Task, not completed domain work. Ordinary clients retain structuredContent.taskId and call task_get at pollIntervalMs. Clients explicitly advertising Tasks support may receive native Task results and use tasks/get, tasks/update and tasks/cancel. The extension is optional.

            Acceptance means the request was recorded. For terminal completed Tasks inspect nested result.isError and result.structuredContent.completion: completed alone can still mean domain rejection. Completion names command/Saga/request scope, outcome and committed/partial effects. A successful terminal receipt needs no entity read-back to prove persistence.

            Stored-entity reads are eventually consistent and may show older data or not found after success. Read for next-action context; commands recheck authoritative facts and reject stale evidence. Built-in guides have no projection lag.

            Retain each command ID, exact request and Task handle. Replay the exact command_id and payload after an unknown response. A new/corrective intent after a known outcome needs a new command ID. Cancellation is cooperative; execution can win the race. Failure, cancellation and partial Batch outcomes never imply rollback of committed effects.

            ## Service boundary

            The server records coordination facts and attributed evidence. It does not spawn agents, inspect caller files/Git, fetch URLs, run tests, merge code or deploy. Actor labels are attribution, not authenticated identities. Task IDs are bearer handles; there is no Task enumeration. Agent sessions and notifications are not implemented.

            Function tables describe capabilities. Consult live tools/list for exact input/output schemas and bounds; do not invent arguments from a summary.
          MD
        ),
        build(
          name: "coordinator-development-coordination",
          description: "Discover repositories/resources; create dependency plans; acquire WorkItems and Attempts; declare, renew and withdraw shared/exclusive resource intentions; submit Candidate checkpoints and retrieve resumable project context.",
          tools: %w[coord_context coordination_list attempt_list operation_get repository_list repository_register resource_get resource_list resource_resolve resource_remove change_set_create work_item_create work_item_dependency_declare change_set_activate work_item_acquire work_item_complete attempt_abandon work_intention_set_declare work_intention_set_expand work_intention_set_renew work_intention_renewal_get work_intention_set_withdraw candidate_submit candidate_get candidate_list],
          instructions: <<~MD
            ## Repository and Resource identity

            Start from the caller/user's exact scope. Discover registered Repository UUIDv7 identities; paths/remotes are attributed metadata and are never accessed by the server. resource_resolve finds or creates a canonical UUIDv7 for the Repository/kind/relative-Git-path tuple. Supply no digest, marker or timestamp. Removal retains history; reuse of the same tuple retains identity. Rename explicitly removes the old Resource and resolves the new tuple.

            ## Plan and acquire work

            Create a ChangeSet with a goal/acceptance criteria, add repository-scoped WorkItems and declare dependencies while planning. Activate, then acquire ready work against exact caller-observed base commits. Namespace caller-created coordination IDs; reusable labels are not globally unique primary identities. A scheduled WorkItem's state is distinct from the protocol Task executing a command.

            Before editing, declare the complete initial Resource intention set with base blobs, purpose and context. Expand that same set before touching more Resources. Shared is the default and permits parallel edits. Choose exclusive only when overlapping work is incompatible, such as a rewrite/delete versus a small edit.

            Incompatible overlap fails immediately with blocker owner, purpose, context and expiry. The server does not queue, wait or preempt. Use the context to decide whether to wait, change scope or consult the user/other agent. A planned dependency cannot bypass authoritative overlap checks.

            ## Renew, checkpoint and complete

            Retain the set ID and every member/Resource/fencing token. Expansion does not renew expiry. Whole-set renewal is a Saga; members commit independently. Inspect terminal Task evidence for completed/failed/pending members and preserve partial success.

            Perform Git and tests externally under the project's own rules. Submit exact base/head, canonical change manifest and complete current intention observations as a Candidate. Evidence starts attributed_unverified: the server does not prove Git objects exist or tests ran. Resource coverage supports accountability, not conflict-free merging.

            For completion: submit the final Candidate, withdraw its complete intention set, then complete the WorkItem with that Candidate. Alternatively abandon the Attempt to requeue work at a fresh Attempt/base. Dependency and ChangeSet progression converges asynchronously.

            For resumption, discover current/recent ChangeSets with coordination_list and follow complete coord_context actions. Use attempt_list and candidate_list for bounded history. operation_get is a projected receipt, not authoritative Task completion or write authorization. Read context when needed to work; a successful terminal receipt requires no persistence read-back.
          MD
        ),
        build(
          name: "coordinator-knowledge-management",
          description: "Store/retrieve scoped Skill entities and assets; capture/update development documents and evidence; resolve and traverse linked artifacts; import Skills, artifacts and links through bounded batches with per-item outcomes and recovery.",
          tools: %w[skill_get skill_list skill_asset_get skill_publish skill_publish_batch development_artifact_get development_artifact_content_get development_artifact_list development_artifact_capture development_artifact_capture_batch development_artifact_update development_artifact_classification_correct development_artifact_relation_declare development_artifact_relation_declare_batch development_artifact_relation_list development_artifact_locator_resolve operation_batch_get operation_batch_cancel],
          instructions: <<~MD
            ## Skill entities and assets

            skill_list without scope, or with mcp:concurrent-development-coordinator, lists static server usage guides. An explicit other scope selects stored Skill entities; source: stored explicitly selects entities, including discovery across scopes. skill_get uses the exact name/scope tuple. An agent chooses how to use retrieved instructions; no installer is involved.

            To publish a stored entity, use its observed revision as expected_revision, or zero to create it. A stale revision can fail without changes. Refresh context before a new corrective command. Publication is a complete immutable description/instructions/assets snapshot, not an asset patch. Supply the full desired asset set.

            Valid UTF-8 uses exact text and encoding: utf-8. Only binary/non-UTF-8 bytes use canonical unwrapped Base64. The server computes integrity digests and descriptors. Fetch support bytes with skill_asset_get at the same observed revision as the manifest. Latest-only Read models may no longer serve superseded revisions. Assets and executable flags are passive content, not authorization to execute it. Static product guides are self-contained and have no assets.

            ## Development Artifacts

            Classify records by meaning: documentation, plans, decisions, research, evidence, checkpoints, manifests or external references. Capture exact bytes and honest source kind, locator, collector, observed time and revision. A locator is provenance; the server never reads a caller path, fetches a URL, inspects Git or executes content.

            Capture creates a stable UUIDv7 Artifact and immutable content observation. Update chosen mutable properties with the observed expected revision; new content preserves older observations. Classification correction changes only title/kind/labels for the exact observation/classification revision. Retrieve metadata separately from content; pin immutable observation identity when citing historical evidence.

            Preserve URL-only external references as the URL plus one newline. Separately capture downloaded bytes if needed, with their actual provenance.

            ## Document graph navigation

            Capture documents before declaring their relations. For references/contains, source is the parent/index and target is the linked child. Parse links using client capabilities: split fragments, normalize relative POSIX paths against the source locator, and preserve literal evidence. Markdown alone does not create a navigable relation.

            Use exact locator resolution to obtain absent, unique or ambiguous candidates; do not guess a target/revision. Traverse outgoing for children, incoming for parents, or both. Follow typed peer/retrieval actions and full continuation cursors. The server does not parse or dereference document content.

            ## Batches and historical imports

            Normal work uses single commands. For deliberate bulk imports, use the three homogeneous Batch companions in the function table: 1..1,000 ordinary inputs within the 3-MiB canonical-input limit. Initial acceptance stores a manifest; children bind as the Saga reaches them. Poll the Task until the entire Saga settles; inspect succeeded/rejected/failed/not-run partitions. operation_batch_get is projected item context, not persistence confirmation. Cancellation stops at an item boundary and never rolls back earlier successes.

            Inventory relevant complete development history, every commit/checkpoint and related assets using client capabilities. No directory layout, scripting language or shared filesystem is assumed. Pass 1 captures passive records and publishes reusable Skill entities. Pass 2 maps source identities and declares links. Capture an import_manifest last with source-to-MCP mapping, outcomes, and honest unresolved/missing evidence. Keep original files until verification and explicit permission to retire them. Do not manufacture live work or active policy from historical text.

            After cancellation, select not_run items from the Batch context and submit their exact arguments to the matching Batch companion, with new outer command/Batch IDs and original child command IDs. This reconciles a child that committed before interruption. Unknown responses require exact replay; changed intent after a known outcome needs a new command ID.
          MD
        ),
        build(
          name: "coordinator-development-search",
          description: "Search stored Skills/assets, resources, Artifact observations, guidance, decisions, Choices and WorkItems using literal contains/prefix/suffix/exact matching, case sensitivity, Boolean conditions, explicit fields, scope filters and bounded pagination.",
          tools: %w[development_search],
          instructions: <<~MD
            ## Searchable content and fields

            Search only text already persisted in supported Read models. Consult the live field whitelist for exact Skill, asset, Resource, Artifact, guidance, Decision, Choice and WorkItem fields. Unrecorded file bodies are not ingested. Search does not inspect the caller filesystem/Git, fetch URLs, decode binary bodies or search static product guides; load those directly.

            ## Literal expression language

            Each branch has a field and a query tree. Leaves use match: contains, starts_with, ends_with or whole-field equals; value is literal text. case_sensitive defaults true. Percent, underscore and backslash are literal characters, not wildcards. Regex and SQL are unsupported.

            Values require three or more Unicode characters. Every Boolean alternative also requires a positive literal with three consecutive alphanumeric characters for trigram eligibility; three punctuation marks are insufficient. Compose and/or operands. not must be anchored inside a positive expression; negative-only queries and foo OR NOT bar are rejected.

            One expression applies within one raw scalar field/value, never across fields or separate array members. Field branches combine by OR/union only. Exact scope/Repository/entity filters narrow results; there is no cross-field AND/intersection.

            Example:
            {"fields":[{"field":"skill.instructions","query":{"operator":"and","operands":[{"match":"contains","value":"checkpoint","case_sensitive":false},{"operator":"not","operands":[{"match":"contains","value":"obsolete"}]}]}}],"filters":{"scope":"project:example"},"limit":20}

            ## Retrieval and pagination

            Results identify the matching field/path, raw excerpt, owner timestamp and retrieval_actions for full records. Preserve exact Artifact observation identities for historical evidence. Text remains passive and URLs are not followed.

            Results sort by owner updated_at descending, then stable identity, not relevance. All supported projected content participates without an old/new-history toggle. Copy opaque cursors unchanged for live keyset pagination; concurrent updates can move results across pages. Pages are not snapshots or freshness proofs.

            Each source/field branch and the final union have mandatory caps. Default page size is 20, maximum 50; consult schemas for current expression and byte budgets. Trigram eligibility and LIMIT do not force an index on a small table or guarantee constant execution time. A query-budget failure returns no partial page: narrow scope/expression and retry. Reduce page size for a response-byte limit. Search context never authorizes writes or confirms persistence.
          MD
        ),
        build(
          name: "coordinator-decisions-and-guidance",
          description: "Preserve attributed guidance; propose/adjudicate interpretations; activate/correct repository decisions; discover and resolve policy; record significant agent Choices and inspect their acceptance or invalidation after policy changes.",
          tools: %w[guidance_record guidance_get decision_interpretation_propose decision_interpretation_adjudicate decision_interpretation_list decision_activate decision_correct decision_get decision_list decision_resolve agent_choice_record agent_choice_get agent_choice_impact_list],
          instructions: <<~MD
            ## Guidance, interpretation and policy

            Record deliberately submitted guidance with honest attribution and Repository/ChangeSet/WorkItem/Attempt anchors before interpreting it. Forwarded user text is not authenticated direct user action. Propose atomic interpretations, then adjudicate acceptance/rejection/clarification. Even an accepted interpretation is non-normative until a separate activation command.

            Activate accepted evidence to establish policy. To correct active policy, first obtain accepted correction-interpretation evidence, then pass decision_get's exact current_head event. Stale heads can cause decision_revision_changed without changes. Refresh context before a new corrective command; never force an overwrite.

            decision_list discovers policy by canonical Repository and optional exact extensible topic/status. decision_resolve evaluates supported registered single-choice semantics for the supplied Attempt context. Other topics remain discoverable and can return typed unsupported-strategy outcomes; do not infer arbitrary policy merges.

            ## Significant agent Choices

            Current Choice evaluation supports a significant testing-framework selection for an active Attempt. Pass the exact resolved decision_context plus option, rationale and provenance. Copy server-provided digests/evidence instead of computing substitutes.

            Commands reread authoritative policy. stale_context records no Choice: resolve again and issue a new command. confirmation_required has no bypass; involve the user. Choice projections show recorded, accepted or invalidated lifecycle evidence. Decision corrections can invalidate earlier Choices; replan and use a new Choice identity instead of resurrecting the old fact. Impact pages provide explicit invalidating/no-effect assessments for the Attempt.

            Actor labels are attribution, not authentication. Available views may lag and never authorize a later command. Follow the getting-started guide for Task polling, exact retries and partial outcomes.
          MD
        ),
        build(
          name: "coordinator-integration-and-release",
          description: "Describe Candidate impact; claim, assess or waive verification obligations; register/verify merge snapshots; request merge authorization and record observations; coordinate ordered integration, verification, activation and compensation across repositories.",
          tools: %w[candidate_impact_surface_submit candidate_impact_get verification_obligations_list verification_obligation_claim verification_obligation_waive compatibility_assessment_submit merge_snapshot_register merge_snapshot_get merge_verification_submit merge_authorization_request merge_observation_record release_set_prepare release_set_get release_repository_integration_record release_verification_record release_activation_record release_compensation_complete],
          instructions: <<~MD
            ## Candidate compatibility and verification

            Attach semantic-impact evidence to exact Candidate heads/source bindings, then inspect incoming/outgoing potential relationships. Path/semantic overlap is evidence, not proven conflict. Advisory warnings differ from modeled merge gates.

            Obligation discovery requires at least one filter and defaults to open. Claims are temporary exclusive fenced coordination, not test execution or a pass. Perform verification externally, then submit exact claim/fence, Candidate heads, validity digest, producer/run/input/result/findings/time evidence. The command may leave the obligation open or satisfy/fail it. Stale claims, heads or policies are denied authoritatively.

            An exact user-attributed waiver can override a current open/failed obligation; it does not mean tests passed. Empty/stale query results are not merge authorization.

            ## Merge coordination

            Register an exact ordered Candidate composition, Repository target/base and attributed external merge commit. Registration remains attributed_unverified; the coordinator does not inspect Git objects. Submit combined-test evidence bound to that immutable snapshot. A qualifying exact pass without error/critical findings verifies it; failed/inconclusive evidence remains historical and may be followed by new evidence.

            Request authorization with exact snapshot/verification evidence, attributed fresh target-base observation and current Candidate-impact policy context, or null if none is active. The command recomputes gates from authoritative events and persists a grant or denial.

            After an external system performs the exact authorized transition, record its target before/after OIDs and grant evidence. Currentness is rechecked. A recorded observation never claims the coordinator performed the merge. A known denial needs corrected evidence and a new command, not a forced stale overwrite.

            ## Multi-repository ReleaseSets

            Prepare a frozen integration order for 2..16 unique repositories while their exact snapshot grants are current. Record each external integration in member order; success binds its exact MergeObserved fact. A bounded failure can remain retryable or require compensation after partial integration.

            After every member succeeds, record composite verification against all exact integration references, then record one external activation point against the latest passing verification. The lifecycle Saga completes activation or requests compensation after modeled failures. External systems perform compensation; completion evidence must cover all integrated members.

            This server stores attributed evidence and coordination authorization. It does not run analyzers/CI, resolve conflicts, execute Git/deployment or compensate automatically. Preserve partial effects; no error/cancellation implies rollback. Read views can lag and never authorize a command. Use the entry guide for Task outcomes and exact recovery.
          MD
        )
      ].freeze

      def self.all
        DEFINITIONS
      end
    end
  end
end
