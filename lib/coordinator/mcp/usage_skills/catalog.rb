# frozen_string_literal: true

module Coordinator::Mcp
  module UsageSkills
    # Distribution input, not a query fallback or repository governance ledger.
    # Installation publishes normal versioned Skills through the public MCP API.
    class Catalog
      SCOPE = "mcp:concurrent-development-coordinator"
      RELEASE = 1
      ENTRY_SKILL = "coordinator-getting-started"

      DEFINITIONS = [
        Definition.new(
          name: ENTRY_SKILL,
          description: "Start using Concurrent Development Coordinator: discover project context, understand durable Tasks and outcomes, recover interrupted requests, and select a focused usage guide.",
          tools: %w[task_get task_cancel],
          instructions: <<~MD
            # Getting started with Concurrent Development Coordinator

            Use this MCP to coordinate checkpointed concurrent development across repositories and retain development knowledge. It records plans, Attempts, Resource intentions, checkpoints, decisions, Skills and Artifacts. It does not spawn agents, inspect caller files/Git, fetch URLs, run CI, or merge code. Actor IDs are attribution labels, not authenticated identities. Task IDs are bearer handles, not sessions; there is no Task enumeration.

            ## Load only the guide needed now

            All product usage guides have exact scope `mcp:concurrent-development-coordinator`:

            - `coordinator-development-coordination`: discover/register repositories, plan and acquire work, declare advisory intentions, checkpoint and complete it.
            - `coordinator-knowledge-management`: publish Skills/assets, capture/update/link Artifacts, or import existing development memory in batches.
            - `coordinator-development-search`: find relevant stored text with bounded literal/Boolean queries.
            - `coordinator-decisions-and-guidance`: preserve user guidance, activate/correct policy and record policy-bound agent Choices.
            - `coordinator-integration-and-release`: coordinate Candidate verification, external merges and multi-repository release evidence.

            Retrieve a guide with `skill_get` using its exact name and scope. `skill_list` discovers names/descriptions; scope has no implicit hierarchy or precedence. Product guides explain the service, not a project's rules: separately load that project's selected guidance, Skills and active decisions. Follow live `tools/list` input/output schemas rather than inventing parameters or treating examples as complete requests.

            ## Durable asynchronous requests

            Domain mutations return a durable Task, not a completed domain operation. Ordinary clients receive normal tool results: retain `structuredContent.taskId` and call `task_get` with `task_id` at `pollIntervalMs`. Clients need not advertise Tasks support. Only explicitly opted-in modern clients receive native `CreateTaskResult` and may use `tasks/get`, `tasks/update`, and `tasks/cancel` instead.

            While working, requested effects are not confirmed. For a completed Task inspect its nested `result.isError` and `result.structuredContent.completion`: status alone is not success. Completion identifies command/Saga/request scope, outcome and committed/partial effects. Request acceptance does not establish downstream completion. A successful terminal receipt needs no entity read-back to prove persistence. Read entities when their content is needed for the next decision.

            Read tools serve available projections and may show older content or not found after a successful write. Task outcomes are authoritative and do not wait for projections. Commands recheck authoritative facts and may reject choices based on stale views; correct the evidence before making a new request.

            ## Recovery and cancellation

            Persist each command ID, exact input and Task handle. After an unknown response replay the exact `command_id` and payload to recover its original Task. Do not create a new mutation merely to confirm persistence. After a known denial, changed/corrective intent uses a new command ID.

            Use `task_cancel` for cooperative cancellation and `task_get` for the outcome. Acknowledgement does not establish terminal cancellation; execution can win the race. Failed/cancelled Tasks and partial Batch outcomes do not imply rollback or cancellation of related operations. Notifications and resumable agent sessions are not provided.
          MD
        ),
        Definition.new(
          name: "coordinator-development-coordination",
          description: "Coordinate single- or multi-repository development: recover project context, plan WorkItems, acquire Attempts, declare shared/exclusive Resource intentions and record checkpoint Candidates.",
          tools: %w[coord_context coordination_list attempt_list operation_get repository_list repository_register resource_get resource_list resource_resolve resource_remove change_set_create work_item_create work_item_dependency_declare change_set_activate work_item_acquire work_item_complete attempt_abandon work_intention_set_declare work_intention_set_expand work_intention_set_renew work_intention_renewal_get work_intention_set_withdraw candidate_submit candidate_get candidate_list],
          instructions: <<~MD
            # Checkpointed development coordination

            Apply `coordinator-getting-started` in scope `mcp:concurrent-development-coordinator` for Task outcomes and retry rules. Use live tool schemas for complete inputs. IDs are concrete identities; human/local labels can repeat across projects, so namespace external coordination IDs rather than assuming a local label is globally unique.

            ## Recover context and choose work

            A clean client with an exact project scope starts with `coordination_list` and follows complete `coord_context` actions. This discovers current/recent ChangeSets, not arbitrary Tasks. `coord_context` accepts supported ChangeSet/WorkItem/Attempt anchors; `attempt_list` discovers observed Attempts. Views can lag. `operation_get` is a projected receipt, not an authorization/freshness gate or a replacement for authoritative Task polling.

            Use `repository_list` to find exact Repository UUIDv7 identities; use `repository_register` to record a repository's caller-known key, scope, paths and remotes. The server does not inspect those paths or contact Git. `resource_list`/`resource_get` expose observed Resource identities; `resource_resolve` finds or creates a stable UUIDv7 for the normalized Repository/kind/path tuple. `resource_remove` records removal without erasing history; reusing the same tuple retains identity. Do not invent Resource IDs from digests or paths.

            ## Plan, acquire, declare

            1. `change_set_create` records the multi-repository goal/acceptance criteria. Add repository-scoped units with `work_item_create`; express ordering through `work_item_dependency_declare` while planning.
            2. `change_set_activate` starts progression. `work_item_acquire` acquires ready work and starts one Attempt with exact caller-observed Git base snapshots. Competing/stale requests are resolved from authoritative facts, not the view that suggested work was ready.
            3. Before editing, use `work_intention_set_declare` for the complete initial Resource set. Expand that same set with `work_intention_set_expand` before touching additional Resources. Include base blobs, purpose and context; explain why work is shared or exclusive.

            Shared is the default. Shared intentions may overlap: parallel work is permitted, not guaranteed to merge cleanly. Choose exclusive only when meaningful planning shows overlapping work is incompatible, such as a rewrite/delete versus a small edit. Any overlap involving exclusive fails immediately with owner, purpose, context and expiry. The server does not queue, wait, preempt or promise eventual exclusive acquisition. Use that context to decide with the other agent/user whether to wait, change scope or reorder work. A planned dependency is not a lock guard; stale clients can still try conflicting commands and receive authoritative denials.

            ## Maintain ownership and checkpoint

            Retain the exact set ID, every intention ID/Resource ID and fencing token. Expand does not renew expiry. `work_intention_set_renew` renews the complete observed set through a bounded Saga; `work_intention_renewal_get` provides projected member context, not durability proof. Use Task outcome evidence for completed/failed/pending members and retain partial success on failure.

            `candidate_submit` records an attributed repository checkpoint at an exact head/base with a typed change manifest and the complete current intention set/fences. Follow project-specific validation/commit rules; the coordinator does not run Git or CI. Uncovered changes or stale observations are denied. Candidate evidence remains `attributed_unverified` until the relevant external evidence is recorded. `candidate_get` returns observed evidence components; `candidate_list` retains bounded checkpoint history; `coord_context` carries the latest observed checkpoint per Attempt.

            For final completion: submit the final Candidate, withdraw the exact full set through `work_intention_set_withdraw`, then select that Candidate with `work_item_complete`. Dependency/ChangeSet progress converges asynchronously; older readable context is normal. If the Attempt is being abandoned instead, use `attempt_abandon` according to its schema rather than fabricating a completion. For impact/merge/release workflows load `coordinator-integration-and-release` in the same product scope.
          MD
        ),
        Definition.new(
          name: "coordinator-knowledge-management",
          description: "Store and retrieve reusable Skills/assets and linked Development Artifacts; update immutable observations, resolve documentation links and migrate development memory through bounded Batch Sagas.",
          tools: %w[skill_get skill_list skill_asset_get skill_publish skill_publish_batch development_artifact_get development_artifact_content_get development_artifact_list development_artifact_capture development_artifact_capture_batch development_artifact_update development_artifact_classification_correct development_artifact_relation_declare development_artifact_relation_declare_batch development_artifact_relation_list development_artifact_locator_resolve operation_batch_get operation_batch_cancel],
          instructions: <<~MD
            # Skills, development knowledge and imports

            Apply `coordinator-getting-started` in scope `mcp:concurrent-development-coordinator` for asynchronous outcomes, exact retries and eventual reads. These tools store caller-supplied facts/bytes. The server cannot read caller paths, inspect Git, fetch locators/URLs or execute stored content.

            ## Version reusable Skills and assets

            `skill_list` discovers exact, case-sensitive names/scopes. Equal names in different scopes are separate Skills; the server infers no hierarchy. `skill_get` retrieves the latest available snapshot. A supplied revision pins that observation, not an indefinitely retained historical read slice: superseded Skill/asset revisions may be unavailable. Reload current metadata rather than mixing bytes from different revisions. For publication, use its observed revision as `skill_publish.expected_revision`; zero creates the tuple. A stale revision can fail with `skill_revision_conflict` without changing the Skill; refresh context and make a new corrective command rather than bypassing the check.

            Every publication is a complete immutable description/instructions/assets snapshot, not an asset patch. Supply all assets intended for that revision. Valid UTF-8 uses `encoding: utf-8` and exact `text`; only binary/non-UTF-8 assets use canonical unwrapped Base64. The server computes integrity digests and text encoding details; do not script client-side digests or Base64 for text. `skill_asset_get` with the pinned Skill revision/path retrieves matching support bytes and executable metadata. Inspect and authorize passive assets externally before executing them.

            ## Capture, evolve and retrieve Artifacts

            Classify by meaning, not filenames alone: documentation, decisions, plans, evidence, checkpoints, URLs and other development assets can be Artifacts. `development_artifact_capture` creates a stable UUIDv7 Artifact and immutable content observation with caller-owned provenance. Preserve exact bytes and honest source kind/locator/collector/revision/observation time. A locator is provenance, never a fetch instruction. A URL-only reference is `external_reference` whose content is the URL plus one newline; a later downloaded response is a separate capture with its own provenance.

            `development_artifact_get` exposes available classification/provenance and observation identity; `development_artifact_content_get` retrieves the selected bytes. Pass exact observation identity when citing historical evidence. `development_artifact_list` discovers scoped/classified objects. To change chosen properties or add new content/source evidence, use `development_artifact_update` with the observed stream revision; commands reject stale revisions while views remain readable. `development_artifact_classification_correct` corrects title/kind/labels using the observed classification revision, never content bytes or provenance.

            ## Linked documents are navigable

            Capture documents first, retaining each Artifact/observation identity. Then use `development_artifact_relation_declare` to connect a source to an explicit internal Artifact/observation, unresolved locator or external reference using the schema's typed relation. Declare parent/child/collection semantics when warranted; do not assume a Markdown link alone creates a navigable relation.

            `development_artifact_relation_list` traverses available incoming/outgoing relations with typed peer/follow actions. `development_artifact_locator_resolve` resolves links using caller-supplied locator/base context and returns absent, unique or ambiguous candidates. Follow exact actions and provenance; do not silently choose an ambiguous match or guess that a source was fetched. Correction/supersession keeps historical evidence; relation types define inverse and transitive behavior, not an unrestricted filesystem crawl.

            ## Import existing development memory

            Inspect that project with the client's own available capabilities, never by a server-prescribed directory layout or required scripting runtime. First inventory semantically relevant complete history, every commit/checkpoint and related assets/provenance within the user's authorized scope. Do not fabricate live WorkItems or active decisions from historical text.

            Pass 1: publish reusable instructions/assets with `skill_publish` or `skill_publish_batch`; capture exact passive records with `development_artifact_capture` or `development_artifact_capture_batch`. Pass 2: connect captured identities through single/batched relation declarations. Use homogeneous bounded batches within live schemas, stable command/Batch identities and exact resumption inputs. These are Sagas, not one transaction over the import. Poll Tasks for authoritative partitioned success/rejection/failure/not-run counts; `operation_batch_get` is projected per-item context. `operation_batch_cancel` is cooperative and never rolls back successful items.

            Capture an `import_manifest` last, including source-to-MCP identity mapping, honest missing evidence and terminal outcomes. Preserve source files until verification and explicit user permission to retire them. A repository AGENTS entry can then point to authoritative MCP context rather than recreating a local coordination ledger. Use reads for semantic content/relationship verification, never merely to reconfirm a successful terminal write receipt.
          MD
        ),
        Definition.new(
          name: "coordinator-development-search",
          description: "Find stored development text without loading whole histories: build scoped literal/Boolean search expressions, understand match fields and limits, and retrieve complete context from returned actions.",
          tools: %w[development_search],
          instructions: <<~MD
            # Search stored development context

            `development_search` is an immediate read over text already projected from stored events: Skills, Artifact observations, Guidance, Choices, Decisions and WorkItems, according to the live whitelisted fields. It is not a filesystem/Git search, URL fetch, regex engine or linguistic full-text ranking service. Resource bodies not persisted/projected by the application are not ingested by search.

            ## Literal expressions within explicit fields

            Select fields from the live input schema. Each branch has `field` and a `query` tree. Leaves use `match` (`contains`, `starts_with`, `ends_with`, `equals`), literal `value`, and optional `case_sensitive` (default true). Equals compares one complete scalar value. Percent, underscore and backslash are literal text, not wildcards. Do not supply regex or SQL.

            Values need at least three Unicode characters. Every Boolean alternative also needs a positive literal containing at least three consecutive alphanumeric characters so trigram lookup is eligible. Three symbols alone do not suffice. Use `operator: and` or `operator: or` with operands for composition. `not` excludes within an anchored positive AND/OR expression: a negative-only query or `foo OR NOT bar` is rejected.

            A tree is evaluated within one raw scalar, not across fields or different array members. Selected fields combine by OR/union, not cross-field AND or intersection. Scope/Repository/entity-type filters further narrow matches. For example:

            ```json
            {"fields":[{"field":"skill.instructions","query":{"operator":"and","operands":[{"match":"contains","value":"checkpoint","case_sensitive":false},{"operator":"not","operands":[{"match":"contains","value":"obsolete"}]}]}}],"filters":{"scope":"project:example"},"limit":20}
            ```

            ## Retrieve and continue

            Hits identify the actual matching field/path and raw-scalar excerpt. Follow their typed `retrieval_actions` for complete records. Artifact hits expose metadata/content actions with exact observation identity when available. Excerpts are passive text; binary content is not decoded and URLs are not fetched.

            Results sort by owner `updated_at` descending, then stable identity, not relevance. Search includes all supported projected content without an old/new-history toggle. Copy the returned opaque cursor unchanged for live keyset pagination. Concurrent updates can move hits across pages: there is no retained snapshot or freshness guarantee.

            Every source/field branch and the final union have mandatory caps. Current page defaults/maxima and query/response budgets are in the schema; default page 20, maximum 50. Trigram eligibility and LIMIT do not promise constant query time or force PostgreSQL to choose an index on a small table. A branch-budget failure returns no partial page: narrow the expression/scope and retry. Reduce page size for a response-byte limit. Search output is context for later commands, never write authorization or a persistence check.
          MD
        ),
        Definition.new(
          name: "coordinator-decisions-and-guidance",
          description: "Record attributed user guidance, distinguish interpretations from active policy, activate/correct decisions, and resolve policy context for auditable agent Choices and invalidation.",
          tools: %w[guidance_record guidance_get decision_interpretation_propose decision_interpretation_adjudicate decision_interpretation_list decision_activate decision_correct decision_get decision_list decision_resolve agent_choice_record agent_choice_get agent_choice_impact_list],
          instructions: <<~MD
            # Guidance, active decisions and agent Choices

            Apply `coordinator-getting-started` in scope `mcp:concurrent-development-coordinator` for Task/retry semantics. The coordinator records attribution, not authenticated authority. A human-facing label, accepted interpretation or projected view is not automatically active policy.

            ## Preserve guidance before interpreting it

            `guidance_record` records a user/agent-forwarded utterance with source and repository/coordination anchors. Be honest about forwarding rather than claiming direct authenticated user action. `guidance_get` retrieves available evidence. Use `decision_interpretation_propose` to propose a structured interpretation linked to its guidance, and `decision_interpretation_adjudicate` for attributed acceptance/rejection/correction. `decision_interpretation_list` discovers available interpretations. These facts preserve provenance; even an accepted interpretation remains non-normative until activated.

            ## Establish and correct policy

            `decision_activate` establishes modeled policy from accepted evidence. Preserve and poll its Task; `decision_get` is latest available evidence, not a freshness proof. `decision_list` discovers projected policy using Repository UUID and an extensible topic.

            For correction, first obtain accepted correction-interpretation evidence, then call `decision_correct` with the exact `current_head` event supplied by `decision_get`. A stale projected head remains readable but can cause an authoritative `decision_revision_changed` conflict. Refresh the context and create a new corrective command; never force an overwrite or disguise a correction as the old request.

            ## Record policy-bound Choices

            `decision_resolve` returns available decision context for an Attempt. Only registered single-choice topics/merge strategies are currently evaluated; unsupported strategies return typed outcomes, not guessed semantics. Before a significant selection in a registered topic, such as a testing framework, pass the exact resolved `decision_context` to `agent_choice_record` with the chosen option, rationale and provenance. Its digests/evidence are server-supplied: copy them rather than inventing client digests.

            The command rereads authoritative policy. `stale_context` means no Choice was recorded: resolve again and submit a new command. `confirmation_required` has no bypass in this protocol; involve the user rather than treating attributed identity as authentication or silently accepting a selection.

            `agent_choice_get` is an available lifecycle view: recorded means its fact is observed, accepted means the next lifecycle fact was observed, invalidated means a Decision change requires replanning. Resolve current decisions and record a new Choice ID after invalidation; do not resurrect the old Choice. `agent_choice_impact_list` provides bounded paginated explicit invalidating/no-effect assessments for an Attempt. These reads may lag and never authorize a later write on their own.
          MD
        ),
        Definition.new(
          name: "coordinator-integration-and-release",
          description: "Use Candidate impact and verification obligations, record externally verified merge snapshots/authorization/observations, and coordinate multi-repository ReleaseSet activation or compensation.",
          tools: %w[candidate_impact_surface_submit candidate_impact_get verification_obligations_list verification_obligation_claim verification_obligation_waive compatibility_assessment_submit merge_snapshot_register merge_snapshot_get merge_verification_submit merge_authorization_request merge_observation_record release_set_prepare release_set_get release_repository_integration_record release_verification_record release_activation_record release_compensation_complete],
          instructions: <<~MD
            # Candidate integration, verification and release evidence

            Apply `coordinator-getting-started` for Task outcomes and `coordinator-development-coordination` for checkpoint submission, both in scope `mcp:concurrent-development-coordinator`. The server records attributed evidence and authorizations; it does not inspect Git, run analyzers/CI, resolve merge conflicts or execute releases. Perform external operations only with the appropriate user/system authority.

            ## Assess Candidate interaction

            `candidate_impact_surface_submit` attaches one attributed semantic surface to an exact Candidate head/source-evidence binding; it does not prove an analyzer ran. `candidate_impact_get` requires incoming/outgoing direction and returns bounded available potential relationships and optional policy summary. Path/semantic matches are evidence, not proven incompatibility. Advisory warnings recommend external verification; they do not create a merge gate.

            For modeled gates, `verification_obligations_list` needs at least one filter and defaults to open; explicitly request satisfied/failed when needed. Empty/older views can reflect projection lag and are not merge authorization. `verification_obligation_claim` grants temporary exclusive coordination; retain the returned claim ID/fencing token. Claiming does not mean execution started or passed.

            Perform verification externally, then use `compatibility_assessment_submit` with the exact claim fence, immutable Candidate heads and validity digest. Record honest producer/run/input/result/findings/time evidence. An assessment can leave an obligation open or satisfy/fail it; stale claims, Candidate bindings and policy are denied authoritatively. A user may explicitly waive an exact current open/failed obligation through `verification_obligation_waive`; attribution is not authentication, and waiver never means verification passed.

            ## Register, verify, authorize, observe an external merge

            1. `merge_snapshot_register` binds an external producer's exact ordered Candidate composition to one Repository target/base/merge commit. Immutable Candidate/manifest bindings are rechecked; registration is still `attributed_unverified` rather than proof the Git object exists.
            2. `merge_snapshot_get` supplies available evidence. `merge_verification_submit` requires the exact full snapshot binding and attributed combined-test results. Failed/inconclusive/not-applicable evidence remains historical and can be followed by new evidence. An exact pass without error/critical findings verifies that immutable snapshot in the same command.
            3. `merge_authorization_request` supplies the exact registered/verified evidence, attributed fresh target-base observation and current Candidate-impact policy context (or null if none is active). It recomputes gates from authoritative facts. A structured denial is durable; correct evidence before a new request. A stale view is never authorization.
            4. After an external system completes the exact authorized transition, use `merge_observation_record` with the grant event/digest and target before/after OIDs. Currentness is rechecked; a recorded observation is attributed, not a claim that this server performed or inspected the merge.

            ## Coordinate a multi-repository ReleaseSet

            `release_set_prepare` freezes 2..16 unique repositories into one semantic integration order once exact snapshot grants are current. All authorizations are re-evaluated. `release_set_get` is an available, possibly stale lifecycle view, never write authorization.

            Record external integrations with `release_repository_integration_record` in frozen member order. Success binds that member's exact `MergeObserved` fact. A bounded attributed failure stays retryable until prior successful integration makes compensation necessary. After all succeed, `release_verification_record` records exact ordered integration references and composite external evidence. `release_activation_record` records one attributed external activation point against the latest exact passing verification.

            The lifecycle Saga completes activated releases and requests compensation after partial integration/composite failure. External systems perform compensation; `release_compensation_complete` records evidence covering every exact integrated member. Preserve partial effects and correlate evidence to the physical preparation; no result implies automatic rollback. All these mutations are durable Tasks and recheck event facts rather than projection freshness.
          MD
        )
      ].freeze

      def self.all
        DEFINITIONS
      end
    end
  end
end
