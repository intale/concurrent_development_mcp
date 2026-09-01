SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: agent_choice_impacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_choice_impacts (
    assessment_id character varying NOT NULL,
    accepted_choice jsonb NOT NULL,
    assessed_at_domain timestamp(6) without time zone NOT NULL,
    assessed_at_store timestamp(6) without time zone NOT NULL,
    assessment jsonb NOT NULL,
    assessment_actor jsonb NOT NULL,
    assessment_event jsonb NOT NULL,
    attempt_id character varying NOT NULL,
    causation_id character varying,
    choice_id character varying NOT NULL,
    correlation_id character varying,
    created_at timestamp(6) without time zone NOT NULL,
    decision_change jsonb NOT NULL,
    event_global_position bigint NOT NULL,
    markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    outcome character varying NOT NULL,
    policy_version character varying NOT NULL,
    reason character varying NOT NULL,
    source_actor jsonb NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: agent_choices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_choices (
    choice_id character varying NOT NULL,
    accepted_actor jsonb,
    accepted_at_domain timestamp(6) without time zone,
    accepted_at_store timestamp(6) without time zone,
    accepted_causation_id character varying,
    accepted_correlation_id character varying,
    accepted_event jsonb,
    accepted_markers jsonb,
    accepted_metadata jsonb,
    alternatives jsonb DEFAULT '[]'::jsonb NOT NULL,
    assessment jsonb,
    choice_type character varying NOT NULL,
    context jsonb NOT NULL,
    context_digest character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    decision_context jsonb NOT NULL,
    invalidated_actor jsonb,
    invalidated_at_domain timestamp(6) without time zone,
    invalidated_at_store timestamp(6) without time zone,
    invalidated_causation_id character varying,
    invalidated_correlation_id character varying,
    invalidated_event jsonb,
    invalidated_markers jsonb,
    invalidated_metadata jsonb,
    invalidation jsonb,
    observation_status character varying NOT NULL,
    reason_summary text NOT NULL,
    recorded_actor jsonb NOT NULL,
    recorded_at_domain timestamp(6) without time zone NOT NULL,
    recorded_at_store timestamp(6) without time zone NOT NULL,
    recorded_causation_id character varying,
    recorded_correlation_id character varying,
    recorded_event jsonb NOT NULL,
    recorded_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    recorded_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    selected jsonb NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: attempt_histories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attempt_histories (
    attempt_id character varying NOT NULL,
    abandonment_reason character varying,
    agent_id character varying NOT NULL,
    authorization_event jsonb DEFAULT '{}'::jsonb NOT NULL,
    authorized_at_domain timestamp(6) without time zone NOT NULL,
    authorized_global_position bigint NOT NULL,
    base_snapshots jsonb DEFAULT '[]'::jsonb NOT NULL,
    change_set_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    selected_candidate_event jsonb,
    selected_candidate_id character varying,
    started_at_domain timestamp(6) without time zone,
    status character varying NOT NULL,
    terminal_at_domain timestamp(6) without time zone,
    terminal_event jsonb,
    updated_at timestamp(6) without time zone NOT NULL,
    work_item_id character varying NOT NULL,
    write_set_lease_set_id character varying,
    write_set_repository_id character varying,
    write_set_policy_version character varying,
    write_set_resources jsonb DEFAULT '[]'::jsonb NOT NULL,
    write_set_reserved_event jsonb,
    write_set_reserved_at_domain timestamp(6) without time zone,
    write_set_last_expanded_event jsonb,
    write_set_last_expanded_at_domain timestamp(6) without time zone,
    write_set_last_renewed_event jsonb,
    write_set_last_renewed_at_domain timestamp(6) without time zone,
    write_set_previous_expires_at_domain timestamp(6) without time zone,
    write_set_expires_at_domain timestamp(6) without time zone,
    write_set_release_event jsonb,
    write_set_released_at_domain timestamp(6) without time zone
);


--
-- Name: candidate_changed_resources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.candidate_changed_resources (
    candidate_id character varying NOT NULL,
    change_set_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    path character varying NOT NULL,
    repository_id character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: candidate_impact_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.candidate_impact_keys (
    candidate_id character varying NOT NULL,
    change_set_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    direction character varying NOT NULL,
    impact_key character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: candidate_observed_inputs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.candidate_observed_inputs (
    candidate_id character varying NOT NULL,
    change_set_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    path character varying NOT NULL,
    repository_id character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: candidates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.candidates (
    candidate_id character varying NOT NULL,
    agent_id character varying NOT NULL,
    attempt_id character varying NOT NULL,
    base_commit_oid character varying NOT NULL,
    build_context jsonb,
    build_context_actor jsonb,
    build_context_at_domain timestamp(6) without time zone,
    build_context_at_store timestamp(6) without time zone,
    build_context_causation_id character varying,
    build_context_correlation_id character varying,
    build_context_digest character varying,
    build_context_event jsonb,
    build_context_global_position bigint,
    build_context_markers jsonb,
    build_context_metadata jsonb,
    change_set_id character varying NOT NULL,
    checkpoint_kind character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    evidence_status character varying NOT NULL,
    head_commit_oid character varying NOT NULL,
    impact_actor jsonb,
    impact_at_domain timestamp(6) without time zone,
    impact_at_store timestamp(6) without time zone,
    impact_causation_id character varying,
    impact_correlation_id character varying,
    impact_event jsonb,
    impact_global_position bigint,
    impact_markers jsonb,
    impact_metadata jsonb,
    impact_surface jsonb,
    lease_policy_version character varying NOT NULL,
    lease_references jsonb DEFAULT '[]'::jsonb NOT NULL,
    lease_set_id character varying NOT NULL,
    manifest jsonb,
    manifest_actor jsonb,
    manifest_at_domain timestamp(6) without time zone,
    manifest_at_store timestamp(6) without time zone,
    manifest_causation_id character varying,
    manifest_correlation_id character varying,
    manifest_digest character varying NOT NULL,
    manifest_event jsonb,
    manifest_global_position bigint,
    manifest_markers jsonb,
    manifest_metadata jsonb,
    object_format character varying NOT NULL,
    repository_id character varying NOT NULL,
    submitted_actor jsonb NOT NULL,
    submitted_at_domain timestamp(6) without time zone NOT NULL,
    submitted_at_store timestamp(6) without time zone NOT NULL,
    submitted_causation_id character varying,
    submitted_correlation_id character varying,
    submitted_event jsonb NOT NULL,
    submitted_global_position bigint NOT NULL,
    submitted_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    submitted_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    target_branch character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    work_item_id character varying NOT NULL
);


--
-- Name: command_receipts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.command_receipts (
    command_id character varying NOT NULL,
    canonical_input_digest character varying NOT NULL,
    command_stream_revision bigint NOT NULL,
    completed_at_domain timestamp(6) without time zone NOT NULL,
    completion jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    receipt character varying NOT NULL,
    status character varying NOT NULL,
    summary character varying NOT NULL,
    tool_name character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: coordinator_contexts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coordinator_contexts (
    change_set_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    document jsonb DEFAULT '{}'::jsonb NOT NULL,
    last_processed_at timestamp(6) without time zone NOT NULL,
    projection_version integer NOT NULL,
    source_positions jsonb DEFAULT '[]'::jsonb NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: coordination_dashboard_work_items; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.coordination_dashboard_work_items AS
 SELECT (work_item.value ->> 'work_item_id'::text) AS work_item_id,
    (work_item.value ->> 'change_set_id'::text) AS change_set_id,
    (work_item.value ->> 'repository_id'::text) AS repository_id,
    (work_item.value ->> 'goal'::text) AS goal,
    COALESCE((work_item.value -> 'acceptance_criteria'::text), '[]'::jsonb) AS acceptance_criteria,
    COALESCE(((work_item.value ->> 'competitive_mode'::text))::boolean, false) AS competitive_mode,
    (work_item.value ->> 'status'::text) AS domain_status,
        CASE
            WHEN ((work_item.value ->> 'status'::text) = 'completed'::text) THEN 'completed'::text
            WHEN ((work_item.value ->> 'status'::text) = 'ready'::text) THEN 'ready'::text
            WHEN (((work_item.value ->> 'status'::text) = 'acquired'::text) AND ((attempt.status)::text = 'started'::text)) THEN 'running'::text
            WHEN ((work_item.value ->> 'status'::text) = 'acquired'::text) THEN 'assigned'::text
            ELSE 'pending'::text
        END AS presentation_status,
    (work_item.value ->> 'active_attempt_id'::text) AS active_attempt_id,
    COALESCE(attempt.agent_id, ((work_item.value ->> 'active_agent_id'::text))::character varying) AS active_agent_id,
    attempt.status AS attempt_status,
    attempt.authorized_at_domain AS attempt_authorized_at,
    attempt.started_at_domain AS attempt_started_at,
    attempt.terminal_at_domain AS attempt_terminal_at,
    (NULLIF((work_item.value ->> 'created_at'::text), ''::text))::timestamp with time zone AS created_at_domain,
    (NULLIF((work_item.value ->> 'made_ready_at'::text), ''::text))::timestamp with time zone AS made_ready_at_domain,
    (NULLIF((work_item.value ->> 'acquired_at'::text), ''::text))::timestamp with time zone AS acquired_at_domain,
    (NULLIF((work_item.value ->> 'completed_at'::text), ''::text))::timestamp with time zone AS completed_at_domain,
    ((context.document -> 'change_set'::text) ->> 'goal'::text) AS change_set_goal,
    COALESCE(((context.document -> 'change_set'::text) -> 'acceptance_criteria'::text), '[]'::jsonb) AS change_set_acceptance_criteria,
    ((context.document -> 'change_set'::text) ->> 'status'::text) AS change_set_status,
    context.last_processed_at
   FROM ((public.coordinator_contexts context
     CROSS JOIN LATERAL jsonb_array_elements(COALESCE((context.document -> 'work_items'::text), '[]'::jsonb)) work_item(value))
     LEFT JOIN public.attempt_histories attempt ON ((((attempt.attempt_id)::text = (work_item.value ->> 'active_attempt_id'::text)) AND ((attempt.change_set_id)::text = (work_item.value ->> 'change_set_id'::text)) AND ((attempt.work_item_id)::text = (work_item.value ->> 'work_item_id'::text)))));


--
-- Name: coordination_dashboard_change_sets; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.coordination_dashboard_change_sets AS
 SELECT change_set_id,
    repository_id,
    change_set_goal AS goal,
    change_set_acceptance_criteria AS acceptance_criteria,
    change_set_status AS domain_status,
    (count(*))::integer AS work_item_count,
    (count(*) FILTER (WHERE (presentation_status = 'running'::text)))::integer AS running_work_item_count,
    (count(*) FILTER (WHERE (presentation_status = ANY (ARRAY['pending'::text, 'ready'::text, 'assigned'::text]))))::integer AS open_work_item_count,
    max(last_processed_at) AS last_processed_at
   FROM public.coordination_dashboard_work_items work_item
  GROUP BY change_set_id, repository_id, change_set_goal, change_set_acceptance_criteria, change_set_status;


--
-- Name: coordination_dashboard_dependencies; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.coordination_dashboard_dependencies AS
 SELECT (dependency.value ->> 'dependency_id'::text) AS dependency_id,
    (dependency.value ->> 'producer_work_item_id'::text) AS producer_work_item_id,
    (dependency.value ->> 'consumer_work_item_id'::text) AS consumer_work_item_id,
    producer.repository_id AS producer_repository_id,
    consumer.repository_id AS consumer_repository_id,
    (dependency.value ->> 'dependency_kind'::text) AS dependency_kind,
    (dependency.value -> 'required_output'::text) AS required_output,
    (NULLIF((dependency.value ->> 'declared_at'::text), ''::text))::timestamp with time zone AS declared_at_domain,
    (NULLIF((dependency.value ->> 'satisfied_at'::text), ''::text))::timestamp with time zone AS satisfied_at_domain,
    ((dependency.value ->> 'satisfied_at'::text) IS NULL) AS blocking,
    context.last_processed_at
   FROM (((public.coordinator_contexts context
     CROSS JOIN LATERAL jsonb_array_elements(COALESCE((context.document -> 'dependencies'::text), '[]'::jsonb)) dependency(value))
     LEFT JOIN public.coordination_dashboard_work_items producer ON (((producer.change_set_id = (context.change_set_id)::text) AND (producer.work_item_id = (dependency.value ->> 'producer_work_item_id'::text)))))
     LEFT JOIN public.coordination_dashboard_work_items consumer ON (((consumer.change_set_id = (context.change_set_id)::text) AND (consumer.work_item_id = (dependency.value ->> 'consumer_work_item_id'::text)))));


--
-- Name: coordinator_context_scopes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coordinator_context_scopes (
    change_set_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    scope_id character varying NOT NULL,
    scope_kind character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: decision_definitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.decision_definitions (
    decision_id character varying NOT NULL,
    acceptance_event jsonb NOT NULL,
    activated_actor jsonb,
    activated_at_domain timestamp(6) without time zone,
    activated_at_store timestamp(6) without time zone,
    activated_causation_id character varying,
    activated_correlation_id character varying,
    activated_event jsonb,
    activated_markers jsonb,
    activated_metadata jsonb,
    classifier jsonb NOT NULL,
    corrected_actor jsonb,
    corrected_at_domain timestamp(6) without time zone,
    corrected_at_store timestamp(6) without time zone,
    corrected_causation_id character varying,
    corrected_correlation_id character varying,
    corrected_event jsonb,
    corrected_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    corrected_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    correction_count integer DEFAULT 0 NOT NULL,
    correction_rationale jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    definition jsonb NOT NULL,
    definition_digest character varying NOT NULL,
    interpretation_id character varying NOT NULL,
    partitions jsonb DEFAULT '[]'::jsonb NOT NULL,
    policy_status character varying NOT NULL,
    previous_definition_digest character varying,
    proposal_event jsonb NOT NULL,
    rationale jsonb,
    recorded_actor jsonb NOT NULL,
    recorded_at_domain timestamp(6) without time zone NOT NULL,
    recorded_at_store timestamp(6) without time zone NOT NULL,
    recorded_causation_id character varying,
    recorded_correlation_id character varying,
    recorded_event jsonb NOT NULL,
    recorded_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    recorded_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    scope_provenance jsonb NOT NULL,
    slot jsonb,
    source_event jsonb NOT NULL,
    source_message_id character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: decision_interpretations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.decision_interpretations (
    interpretation_id character varying NOT NULL,
    actor_id character varying NOT NULL,
    actor_kind character varying NOT NULL,
    adjudication jsonb,
    ambiguities jsonb DEFAULT '[]'::jsonb NOT NULL,
    assessment jsonb NOT NULL,
    causation_id character varying,
    clarification_event_id character varying,
    clarification_required boolean DEFAULT false NOT NULL,
    clarification_required_at_domain timestamp(6) without time zone,
    clarification_stream_revision bigint,
    classifier jsonb NOT NULL,
    correlation_id character varying,
    created_at timestamp(6) without time zone NOT NULL,
    event_id character varying NOT NULL,
    event_type character varying NOT NULL,
    lifecycle_status character varying DEFAULT 'proposed'::character varying NOT NULL,
    message_id character varying NOT NULL,
    policy_status character varying NOT NULL,
    proposal_status character varying NOT NULL,
    proposed_at_domain timestamp(6) without time zone NOT NULL,
    proposed_decision jsonb NOT NULL,
    scope_provenance jsonb NOT NULL,
    source_event jsonb NOT NULL,
    source_span jsonb,
    stream_context character varying NOT NULL,
    stream_id character varying NOT NULL,
    stream_name character varying NOT NULL,
    stream_revision bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: decision_partition_heads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.decision_partition_heads (
    partition_id character varying NOT NULL,
    active_decisions jsonb DEFAULT '[]'::jsonb NOT NULL,
    actor jsonb NOT NULL,
    advanced_at_domain timestamp(6) without time zone NOT NULL,
    causation_id character varying,
    change_kind character varying NOT NULL,
    correlation_id character varying,
    created_at timestamp(6) without time zone NOT NULL,
    decision jsonb NOT NULL,
    decision_id character varying NOT NULL,
    event jsonb NOT NULL,
    event_created_at timestamp(6) without time zone NOT NULL,
    markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    partition jsonb NOT NULL,
    partition_revision bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: decision_repository_memberships; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.decision_repository_memberships AS
 SELECT decision_id,
    repository_id,
    to_jsonb(array_agg(DISTINCT basis ORDER BY basis)) AS membership_bases
   FROM ( SELECT decision.decision_id,
            repository_id.value AS repository_id,
            'explicit_repository'::text AS basis
           FROM (public.decision_definitions decision
             CROSS JOIN LATERAL jsonb_array_elements_text(COALESCE((decision.definition #> '{document,scope,repository_ids}'::text[]), '[]'::jsonb)) repository_id(value))
        UNION ALL
         SELECT decision.decision_id,
            work_item.repository_id,
            'change_set'::text AS basis
           FROM (public.decision_definitions decision
             JOIN public.coordination_dashboard_work_items work_item ON ((work_item.change_set_id = (decision.definition #>> '{document,scope,change_set_id}'::text[]))))
        UNION ALL
         SELECT decision.decision_id,
            work_item.repository_id,
            'work_item'::text AS basis
           FROM (public.decision_definitions decision
             JOIN public.coordination_dashboard_work_items work_item ON ((work_item.work_item_id = (decision.definition #>> '{document,scope,work_item_id}'::text[]))))
        UNION ALL
         SELECT decision.decision_id,
            work_item.repository_id,
            'attempt'::text AS basis
           FROM ((public.decision_definitions decision
             JOIN public.attempt_histories attempt ON (((attempt.attempt_id)::text = (decision.definition #>> '{document,scope,attempt_id}'::text[]))))
             JOIN public.coordination_dashboard_work_items work_item ON (((work_item.change_set_id = (attempt.change_set_id)::text) AND (work_item.work_item_id = (attempt.work_item_id)::text))))
        UNION ALL
         SELECT decision.decision_id,
            candidate.repository_id,
            'candidate'::text AS basis
           FROM (public.decision_definitions decision
             JOIN public.candidates candidate ON (((candidate.candidate_id)::text = (decision.definition #>> '{document,scope,candidate_id}'::text[]))))) membership
  GROUP BY decision_id, repository_id;


--
-- Name: decision_slot_heads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.decision_slot_heads (
    slot_id character varying NOT NULL,
    actor jsonb NOT NULL,
    causation_id character varying,
    changed_at_domain timestamp(6) without time zone,
    changed_event jsonb,
    correlation_id character varying,
    created_at timestamp(6) without time zone NOT NULL,
    decision_id character varying,
    event_created_at timestamp(6) without time zone NOT NULL,
    head jsonb,
    markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    opened_at_domain timestamp(6) without time zone NOT NULL,
    opened_event jsonb NOT NULL,
    slot jsonb NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: development_artifact_observations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.development_artifact_observations (
    observation_id character varying NOT NULL,
    artifact_id character varying NOT NULL,
    classification_reason text,
    classification_revision integer DEFAULT 1 CONSTRAINT development_artifact_observati_classification_revision_not_null NOT NULL,
    classified_actor jsonb,
    classified_at_domain timestamp(6) without time zone,
    classified_at_store timestamp(6) without time zone,
    classified_causation_id character varying,
    classified_correlation_id character varying,
    classified_event jsonb,
    classified_global_position bigint,
    classified_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    classified_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    current_global_position bigint CONSTRAINT development_artifact_observati_current_global_position_not_null NOT NULL,
    kind character varying,
    labels jsonb DEFAULT '[]'::jsonb NOT NULL,
    observed_actor jsonb,
    observed_at_domain timestamp(6) without time zone,
    observed_at_store timestamp(6) without time zone,
    observed_causation_id character varying,
    observed_correlation_id character varying,
    observed_event jsonb,
    observed_global_position bigint,
    observed_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    observed_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    observed_sequence bigint NOT NULL,
    scope text,
    source_collector character varying,
    source_kind character varying,
    source_locator text,
    source_observed_at timestamp(6) without time zone,
    source_revision text,
    title text,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: development_artifact_observations_observed_sequence_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.development_artifact_observations_observed_sequence_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: development_artifact_observations_observed_sequence_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.development_artifact_observations_observed_sequence_seq OWNED BY public.development_artifact_observations.observed_sequence;


--
-- Name: development_artifact_relation_supersessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.development_artifact_relation_supersessions (
    superseded_relation_id character varying CONSTRAINT development_artifact_relation_s_superseded_relation_id_not_null NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    observed_sequence bigint CONSTRAINT development_artifact_relation_supers_observed_sequence_not_null NOT NULL,
    reason text NOT NULL,
    replacement_relation_id character varying CONSTRAINT development_artifact_relation__replacement_relation_id_not_null NOT NULL,
    source_artifact_id character varying CONSTRAINT development_artifact_relation_super_source_artifact_id_not_null NOT NULL,
    superseded_actor jsonb CONSTRAINT development_artifact_relation_superse_superseded_actor_not_null NOT NULL,
    superseded_at_domain timestamp(6) without time zone CONSTRAINT development_artifact_relation_sup_superseded_at_domain_not_null NOT NULL,
    superseded_at_store timestamp(6) without time zone CONSTRAINT development_artifact_relation_supe_superseded_at_store_not_null NOT NULL,
    superseded_causation_id character varying,
    superseded_correlation_id character varying,
    superseded_event jsonb CONSTRAINT development_artifact_relation_superse_superseded_event_not_null NOT NULL,
    superseded_global_position bigint CONSTRAINT development_artifact_relati_superseded_global_position_not_null NOT NULL,
    superseded_markers jsonb DEFAULT '[]'::jsonb CONSTRAINT development_artifact_relation_super_superseded_markers_not_null NOT NULL,
    superseded_metadata jsonb DEFAULT '{}'::jsonb CONSTRAINT development_artifact_relation_supe_superseded_metadata_not_null NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: development_artifact_relation_supersessio_observed_sequence_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.development_artifact_relation_supersessio_observed_sequence_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: development_artifact_relation_supersessio_observed_sequence_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.development_artifact_relation_supersessio_observed_sequence_seq OWNED BY public.development_artifact_relation_supersessions.observed_sequence;


--
-- Name: development_artifact_relations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.development_artifact_relations (
    relation_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    declared_actor jsonb NOT NULL,
    declared_at_domain timestamp(6) without time zone NOT NULL,
    declared_at_store timestamp(6) without time zone NOT NULL,
    declared_causation_id character varying,
    declared_correlation_id character varying,
    declared_event jsonb NOT NULL,
    declared_global_position bigint CONSTRAINT development_artifact_relation_declared_global_position_not_null NOT NULL,
    declared_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    declared_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    fragment text,
    normalized_locator text,
    observed_sequence bigint NOT NULL,
    path text,
    relation character varying NOT NULL,
    source_artifact_id character varying NOT NULL,
    target_id text NOT NULL,
    target_kind character varying NOT NULL,
    target_name character varying,
    target_scope character varying,
    target_status character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: development_artifact_relations_observed_sequence_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.development_artifact_relations_observed_sequence_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: development_artifact_relations_observed_sequence_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.development_artifact_relations_observed_sequence_seq OWNED BY public.development_artifact_relations.observed_sequence;


--
-- Name: development_artifacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.development_artifacts (
    artifact_id character varying NOT NULL,
    captured_actor jsonb NOT NULL,
    captured_at_domain timestamp(6) without time zone NOT NULL,
    captured_at_store timestamp(6) without time zone NOT NULL,
    captured_causation_id character varying,
    captured_correlation_id character varying,
    captured_event jsonb NOT NULL,
    captured_global_position bigint NOT NULL,
    captured_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    captured_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    content_base64 text,
    content_byte_size bigint NOT NULL,
    content_encoding character varying NOT NULL,
    content_media_type character varying NOT NULL,
    content_sha256 character varying NOT NULL,
    content_text text,
    created_at timestamp(6) without time zone NOT NULL,
    kind character varying NOT NULL,
    labels jsonb DEFAULT '[]'::jsonb NOT NULL,
    observed_sequence bigint NOT NULL,
    scope text NOT NULL,
    source_collector character varying NOT NULL,
    source_kind character varying NOT NULL,
    source_locator text NOT NULL,
    source_observed_at timestamp(6) without time zone NOT NULL,
    source_revision text,
    title text NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: development_artifacts_observed_sequence_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.development_artifacts_observed_sequence_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: development_artifacts_observed_sequence_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.development_artifacts_observed_sequence_seq OWNED BY public.development_artifacts.observed_sequence;


--
-- Name: merge_authorizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merge_authorizations (
    authorization_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    decided_at_domain timestamp(6) without time zone NOT NULL,
    decision_digest character varying NOT NULL,
    evaluation jsonb NOT NULL,
    expected_impact_policy jsonb,
    input_digest character varying NOT NULL,
    merge_snapshot_id character varying NOT NULL,
    outcome character varying NOT NULL,
    policy_version character varying NOT NULL,
    snapshot_binding jsonb NOT NULL,
    source_actor jsonb NOT NULL,
    source_causation_id character varying,
    source_correlation_id character varying,
    source_event jsonb NOT NULL,
    source_global_position bigint NOT NULL,
    source_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    source_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    source_persisted_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: merge_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merge_snapshots (
    merge_snapshot_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    evidence_status character varying NOT NULL,
    merge_commit_oid character varying NOT NULL,
    object_format character varying NOT NULL,
    observation jsonb,
    ordered_candidates jsonb NOT NULL,
    policy_version character varying NOT NULL,
    produced_at_domain timestamp(6) without time zone NOT NULL,
    producer jsonb NOT NULL,
    registered_actor jsonb NOT NULL,
    registered_at_domain timestamp(6) without time zone NOT NULL,
    registered_at_store timestamp(6) without time zone NOT NULL,
    registered_causation_id character varying,
    registered_correlation_id character varying,
    registered_event jsonb NOT NULL,
    registered_global_position bigint NOT NULL,
    registered_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    registered_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    repository_id character varying NOT NULL,
    run_id character varying NOT NULL,
    snapshot_digest character varying NOT NULL,
    target_base_commit_oid character varying NOT NULL,
    target_branch character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    verification_policy_version character varying DEFAULT 'merge-snapshot-verification/v1'::character varying NOT NULL,
    verification_status character varying DEFAULT 'unverified'::character varying NOT NULL,
    verification_submissions jsonb DEFAULT '[]'::jsonb NOT NULL,
    verified_decision jsonb
);


--
-- Name: operation_batch_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.operation_batch_items (
    id bigint NOT NULL,
    arguments jsonb NOT NULL,
    batch_id character varying NOT NULL,
    canonical_input_digest character varying NOT NULL,
    command_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    item_index integer NOT NULL,
    target_tool character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: operation_batch_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.operation_batch_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: operation_batch_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.operation_batch_items_id_seq OWNED BY public.operation_batch_items.id;


--
-- Name: operation_batch_outcomes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.operation_batch_outcomes (
    id bigint NOT NULL,
    batch_id character varying NOT NULL,
    canonical_input_digest character varying NOT NULL,
    command_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    finished_at_domain timestamp(6) without time zone NOT NULL,
    finished_at_store timestamp(6) without time zone NOT NULL,
    item_index integer NOT NULL,
    outcome_actor jsonb NOT NULL,
    outcome_causation_id character varying,
    outcome_correlation_id character varying,
    outcome_event jsonb NOT NULL,
    outcome_global_position bigint NOT NULL,
    outcome_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    outcome_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    result jsonb NOT NULL,
    status character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: operation_batch_outcomes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.operation_batch_outcomes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: operation_batch_outcomes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.operation_batch_outcomes_id_seq OWNED BY public.operation_batch_outcomes.id;


--
-- Name: operation_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.operation_batches (
    batch_id character varying NOT NULL,
    cancellation_actor jsonb,
    cancellation_at_domain timestamp(6) without time zone,
    cancellation_at_store timestamp(6) without time zone,
    cancellation_causation_id character varying,
    cancellation_correlation_id character varying,
    cancellation_event jsonb,
    cancellation_global_position bigint,
    cancellation_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    cancellation_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    cancellation_requested boolean DEFAULT false NOT NULL,
    created_actor jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    created_at_domain timestamp(6) without time zone,
    created_at_store timestamp(6) without time zone,
    created_causation_id character varying,
    created_correlation_id character varying,
    created_event jsonb,
    created_global_position bigint,
    created_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    encoded_byte_size bigint,
    manifest_digest character varying,
    page_size integer,
    rejected_count integer DEFAULT 0 NOT NULL,
    status character varying DEFAULT 'running'::character varying NOT NULL,
    succeeded_count integer DEFAULT 0 NOT NULL,
    target_tool character varying,
    terminal_actor jsonb,
    terminal_at_domain timestamp(6) without time zone,
    terminal_at_store timestamp(6) without time zone,
    terminal_causation_id character varying,
    terminal_correlation_id character varying,
    terminal_event jsonb,
    terminal_global_position bigint,
    terminal_kind character varying,
    terminal_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    terminal_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    total integer,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: processed_projection_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.processed_projection_events (
    command_id character varying,
    event_id character varying NOT NULL,
    event_type character varying NOT NULL,
    processed_at timestamp(6) without time zone NOT NULL,
    projection_name character varying NOT NULL,
    projection_version integer NOT NULL,
    stream_context character varying NOT NULL,
    stream_id character varying NOT NULL,
    stream_name character varying NOT NULL,
    stream_revision bigint NOT NULL
);


--
-- Name: release_sets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.release_sets (
    release_set_id character varying NOT NULL,
    activation jsonb,
    change_set_id character varying NOT NULL,
    compensation_request jsonb,
    completion jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    integrations jsonb DEFAULT '[]'::jsonb NOT NULL,
    ordered_members jsonb NOT NULL,
    preparation_policy_version character varying NOT NULL,
    prepared_actor jsonb NOT NULL,
    prepared_at_domain timestamp(6) without time zone NOT NULL,
    prepared_at_store timestamp(6) without time zone NOT NULL,
    prepared_causation_id character varying,
    prepared_correlation_id character varying,
    prepared_event jsonb NOT NULL,
    prepared_global_position bigint NOT NULL,
    prepared_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    prepared_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    release_digest character varying NOT NULL,
    status character varying DEFAULT 'prepared'::character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    verification_status character varying DEFAULT 'unverified'::character varying NOT NULL,
    verifications jsonb DEFAULT '[]'::jsonb NOT NULL
);


--
-- Name: repositories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.repositories (
    repository_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    display_name character varying,
    paths jsonb DEFAULT '[]'::jsonb NOT NULL,
    registered_actor jsonb NOT NULL,
    registered_at_domain timestamp(6) without time zone NOT NULL,
    registered_at_store timestamp(6) without time zone NOT NULL,
    registered_causation_id character varying,
    registered_correlation_id character varying,
    registered_event jsonb NOT NULL,
    registered_global_position bigint NOT NULL,
    registered_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    registered_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    remotes jsonb DEFAULT '[]'::jsonb NOT NULL,
    scope text NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: resources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resources (
    resource_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    kind character varying NOT NULL,
    latest_transition_actor jsonb,
    latest_transition_at_domain timestamp(6) without time zone,
    latest_transition_at_store timestamp(6) without time zone,
    latest_transition_causation_id character varying,
    latest_transition_correlation_id character varying,
    latest_transition_event jsonb,
    latest_transition_global_position bigint,
    latest_transition_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    latest_transition_metadata jsonb,
    lifecycle_status character varying NOT NULL,
    normalized_path text NOT NULL,
    registered_actor jsonb,
    registered_at_domain timestamp(6) without time zone,
    registered_at_store timestamp(6) without time zone,
    registered_causation_id character varying,
    registered_correlation_id character varying,
    registered_event jsonb,
    registered_global_position bigint,
    registered_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    registered_metadata jsonb,
    repository_id character varying NOT NULL,
    unbinding_reason character varying,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: resource_lease_browser_rows; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.resource_lease_browser_rows AS
 SELECT (membership.value ->> 'lease_id'::text) AS lease_id,
    (membership.value ->> 'resource_id'::text) AS resource_id,
    attempt.write_set_lease_set_id AS lease_set_id,
    attempt.write_set_repository_id AS repository_id,
    repository.scope AS project_scope,
    repository.display_name AS project_name,
    COALESCE(resource.kind, ((membership.value ->> 'resource_kind'::text))::character varying) AS resource_kind,
    COALESCE(resource.normalized_path, (membership.value ->> 'resource_path'::text)) AS resource_path,
    resource.lifecycle_status AS resource_lifecycle_status,
    (membership.value ->> 'base_blob_oid'::text) AS base_blob_oid,
    ((membership.value ->> 'fencing_token'::text))::bigint AS fencing_token,
    attempt.write_set_policy_version AS policy_version,
    attempt.change_set_id,
    attempt.work_item_id,
    attempt.attempt_id,
    attempt.agent_id,
    attempt.write_set_reserved_event AS reserved_event,
    attempt.write_set_reserved_at_domain AS reserved_at_domain,
    attempt.write_set_last_expanded_event AS last_expanded_event,
    attempt.write_set_last_expanded_at_domain AS last_expanded_at_domain,
    attempt.write_set_last_renewed_event AS last_renewed_event,
    attempt.write_set_last_renewed_at_domain AS last_renewed_at_domain,
    attempt.write_set_previous_expires_at_domain AS previous_expires_at_domain,
    attempt.write_set_expires_at_domain AS expires_at_domain,
    attempt.write_set_release_event AS release_event,
    attempt.write_set_released_at_domain AS released_at_domain,
    attempt.terminal_event AS attempt_terminal_event,
    attempt.terminal_at_domain AS attempt_terminal_at_domain,
    attempt.updated_at AS last_projected_at
   FROM (((public.attempt_histories attempt
     JOIN public.repositories repository ON (((repository.repository_id)::text = (attempt.write_set_repository_id)::text)))
     CROSS JOIN LATERAL jsonb_array_elements(attempt.write_set_resources) membership(value))
     LEFT JOIN public.resources resource ON ((((resource.resource_id)::text = (membership.value ->> 'resource_id'::text)) AND ((resource.repository_id)::text = (attempt.write_set_repository_id)::text))))
  WHERE (attempt.write_set_lease_set_id IS NOT NULL);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: skill_assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.skill_assets (
    id bigint NOT NULL,
    byte_size bigint NOT NULL,
    content_base64 text,
    content_encoding character varying NOT NULL,
    content_sha256 character varying NOT NULL,
    content_text text,
    created_at timestamp(6) without time zone NOT NULL,
    executable boolean NOT NULL,
    media_type character varying NOT NULL,
    path text NOT NULL,
    revision bigint NOT NULL,
    skill_id character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: skill_assets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.skill_assets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: skill_assets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.skill_assets_id_seq OWNED BY public.skill_assets.id;


--
-- Name: skill_revisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.skill_revisions (
    id bigint NOT NULL,
    asset_count integer NOT NULL,
    content_digest character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    description text NOT NULL,
    instructions text NOT NULL,
    published_actor jsonb NOT NULL,
    published_at_domain timestamp(6) without time zone NOT NULL,
    published_at_store timestamp(6) without time zone NOT NULL,
    published_causation_id character varying,
    published_correlation_id character varying,
    published_event jsonb NOT NULL,
    published_global_position bigint NOT NULL,
    published_markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    published_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    revision bigint NOT NULL,
    skill_id character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: skill_revisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.skill_revisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: skill_revisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.skill_revisions_id_seq OWNED BY public.skill_revisions.id;


--
-- Name: skills; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.skills (
    skill_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL,
    revision bigint NOT NULL,
    scope text NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: user_utterances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_utterances (
    message_id character varying NOT NULL,
    actor_id character varying NOT NULL,
    actor_kind character varying NOT NULL,
    anchors jsonb DEFAULT '{}'::jsonb NOT NULL,
    causation_id character varying,
    conversation_id character varying NOT NULL,
    correlation_id character varying,
    created_at timestamp(6) without time zone NOT NULL,
    event_id character varying NOT NULL,
    event_type character varying NOT NULL,
    policy_status character varying NOT NULL,
    recorded_at_domain timestamp(6) without time zone NOT NULL,
    source character varying NOT NULL,
    stream_context character varying NOT NULL,
    stream_id character varying NOT NULL,
    stream_name character varying NOT NULL,
    stream_revision bigint NOT NULL,
    text text NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: verification_obligation_evidence_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.verification_obligation_evidence_items (
    evidence_id character varying NOT NULL,
    actor jsonb NOT NULL,
    assessment_input_digest character varying CONSTRAINT verification_obligation_eviden_assessment_input_digest_not_null NOT NULL,
    causation_id character varying,
    conclusion character varying NOT NULL,
    correlation_id character varying,
    created_at timestamp(6) without time zone NOT NULL,
    created_at_store timestamp(6) without time zone CONSTRAINT verification_obligation_evidence_item_created_at_store_not_null NOT NULL,
    event jsonb NOT NULL,
    event_global_position bigint CONSTRAINT verification_obligation_evidence_event_global_position_not_null NOT NULL,
    event_id character varying NOT NULL,
    evidence_kind character varying NOT NULL,
    markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    obligation_id character varying NOT NULL,
    produced_at_domain timestamp(6) without time zone CONSTRAINT verification_obligation_evidence_it_produced_at_domain_not_null NOT NULL,
    result_digest character varying NOT NULL,
    stream_revision integer NOT NULL,
    submission jsonb NOT NULL,
    submitted_at_domain timestamp(6) without time zone CONSTRAINT verification_obligation_evidence_i_submitted_at_domain_not_null NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: verification_obligations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.verification_obligations (
    obligation_id character varying NOT NULL,
    actor jsonb NOT NULL,
    causation_id character varying,
    change_set_id character varying NOT NULL,
    claim jsonb,
    claim_actor jsonb,
    claim_causation_id character varying,
    claim_claimed_at_domain timestamp(6) without time zone,
    claim_correlation_id character varying,
    claim_created_at_store timestamp(6) without time zone,
    claim_event jsonb,
    claim_event_global_position bigint,
    claim_expires_at_domain timestamp(6) without time zone,
    claim_fencing_token integer,
    claim_id character varying,
    claim_markers jsonb,
    claim_metadata jsonb,
    claim_stream_revision integer,
    claimant_id character varying,
    correlation_id character varying,
    created_at timestamp(6) without time zone NOT NULL,
    created_at_domain timestamp(6) without time zone NOT NULL,
    created_at_store timestamp(6) without time zone NOT NULL,
    enforcement character varying NOT NULL,
    event jsonb NOT NULL,
    event_global_position bigint NOT NULL,
    evidence_count integer DEFAULT 0 NOT NULL,
    kind character varying NOT NULL,
    markers jsonb DEFAULT '[]'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    missing_evidence_kinds jsonb DEFAULT '[]'::jsonb NOT NULL,
    obligation jsonb NOT NULL,
    passed_evidence_kinds jsonb DEFAULT '[]'::jsonb NOT NULL,
    source_candidate_id character varying NOT NULL,
    source_repository_id character varying NOT NULL,
    source_work_item_id character varying NOT NULL,
    status character varying NOT NULL,
    target_candidate_id character varying NOT NULL,
    target_repository_id character varying NOT NULL,
    target_work_item_id character varying NOT NULL,
    terminal_actor jsonb,
    terminal_at_domain timestamp(6) without time zone,
    terminal_causation_id character varying,
    terminal_correlation_id character varying,
    terminal_created_at_store timestamp(6) without time zone,
    terminal_event jsonb,
    terminal_event_global_position bigint,
    terminal_markers jsonb,
    terminal_metadata jsonb,
    terminal_outcome jsonb,
    terminal_stream_revision integer,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: development_artifact_observations observed_sequence; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.development_artifact_observations ALTER COLUMN observed_sequence SET DEFAULT nextval('public.development_artifact_observations_observed_sequence_seq'::regclass);


--
-- Name: development_artifact_relation_supersessions observed_sequence; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.development_artifact_relation_supersessions ALTER COLUMN observed_sequence SET DEFAULT nextval('public.development_artifact_relation_supersessio_observed_sequence_seq'::regclass);


--
-- Name: development_artifact_relations observed_sequence; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.development_artifact_relations ALTER COLUMN observed_sequence SET DEFAULT nextval('public.development_artifact_relations_observed_sequence_seq'::regclass);


--
-- Name: development_artifacts observed_sequence; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.development_artifacts ALTER COLUMN observed_sequence SET DEFAULT nextval('public.development_artifacts_observed_sequence_seq'::regclass);


--
-- Name: operation_batch_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operation_batch_items ALTER COLUMN id SET DEFAULT nextval('public.operation_batch_items_id_seq'::regclass);


--
-- Name: operation_batch_outcomes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operation_batch_outcomes ALTER COLUMN id SET DEFAULT nextval('public.operation_batch_outcomes_id_seq'::regclass);


--
-- Name: skill_assets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_assets ALTER COLUMN id SET DEFAULT nextval('public.skill_assets_id_seq'::regclass);


--
-- Name: skill_revisions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_revisions ALTER COLUMN id SET DEFAULT nextval('public.skill_revisions_id_seq'::regclass);


--
-- Name: agent_choice_impacts agent_choice_impacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_choice_impacts
    ADD CONSTRAINT agent_choice_impacts_pkey PRIMARY KEY (assessment_id);


--
-- Name: agent_choices agent_choices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_choices
    ADD CONSTRAINT agent_choices_pkey PRIMARY KEY (choice_id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: attempt_histories attempt_histories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attempt_histories
    ADD CONSTRAINT attempt_histories_pkey PRIMARY KEY (attempt_id);


--
-- Name: candidates candidates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.candidates
    ADD CONSTRAINT candidates_pkey PRIMARY KEY (candidate_id);


--
-- Name: command_receipts command_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_receipts
    ADD CONSTRAINT command_receipts_pkey PRIMARY KEY (command_id);


--
-- Name: coordinator_contexts coordinator_contexts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coordinator_contexts
    ADD CONSTRAINT coordinator_contexts_pkey PRIMARY KEY (change_set_id);


--
-- Name: decision_definitions decision_definitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decision_definitions
    ADD CONSTRAINT decision_definitions_pkey PRIMARY KEY (decision_id);


--
-- Name: decision_interpretations decision_interpretations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decision_interpretations
    ADD CONSTRAINT decision_interpretations_pkey PRIMARY KEY (interpretation_id);


--
-- Name: decision_partition_heads decision_partition_heads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decision_partition_heads
    ADD CONSTRAINT decision_partition_heads_pkey PRIMARY KEY (partition_id);


--
-- Name: decision_slot_heads decision_slot_heads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decision_slot_heads
    ADD CONSTRAINT decision_slot_heads_pkey PRIMARY KEY (slot_id);


--
-- Name: development_artifact_observations development_artifact_observations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.development_artifact_observations
    ADD CONSTRAINT development_artifact_observations_pkey PRIMARY KEY (observation_id);


--
-- Name: development_artifact_relation_supersessions development_artifact_relation_supersessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.development_artifact_relation_supersessions
    ADD CONSTRAINT development_artifact_relation_supersessions_pkey PRIMARY KEY (superseded_relation_id);


--
-- Name: development_artifact_relations development_artifact_relations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.development_artifact_relations
    ADD CONSTRAINT development_artifact_relations_pkey PRIMARY KEY (relation_id);


--
-- Name: development_artifacts development_artifacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.development_artifacts
    ADD CONSTRAINT development_artifacts_pkey PRIMARY KEY (artifact_id);


--
-- Name: merge_authorizations merge_authorizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merge_authorizations
    ADD CONSTRAINT merge_authorizations_pkey PRIMARY KEY (authorization_id);


--
-- Name: merge_snapshots merge_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merge_snapshots
    ADD CONSTRAINT merge_snapshots_pkey PRIMARY KEY (merge_snapshot_id);


--
-- Name: operation_batch_items operation_batch_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operation_batch_items
    ADD CONSTRAINT operation_batch_items_pkey PRIMARY KEY (id);


--
-- Name: operation_batch_outcomes operation_batch_outcomes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operation_batch_outcomes
    ADD CONSTRAINT operation_batch_outcomes_pkey PRIMARY KEY (id);


--
-- Name: operation_batches operation_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operation_batches
    ADD CONSTRAINT operation_batches_pkey PRIMARY KEY (batch_id);


--
-- Name: release_sets release_sets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.release_sets
    ADD CONSTRAINT release_sets_pkey PRIMARY KEY (release_set_id);


--
-- Name: repositories repositories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repositories
    ADD CONSTRAINT repositories_pkey PRIMARY KEY (repository_id);


--
-- Name: resources resources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resources
    ADD CONSTRAINT resources_pkey PRIMARY KEY (resource_id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: skill_assets skill_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_assets
    ADD CONSTRAINT skill_assets_pkey PRIMARY KEY (id);


--
-- Name: skill_revisions skill_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_revisions
    ADD CONSTRAINT skill_revisions_pkey PRIMARY KEY (id);


--
-- Name: skills skills_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skills
    ADD CONSTRAINT skills_pkey PRIMARY KEY (skill_id);


--
-- Name: user_utterances user_utterances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_utterances
    ADD CONSTRAINT user_utterances_pkey PRIMARY KEY (message_id);


--
-- Name: verification_obligation_evidence_items verification_obligation_evidence_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.verification_obligation_evidence_items
    ADD CONSTRAINT verification_obligation_evidence_items_pkey PRIMARY KEY (evidence_id);


--
-- Name: verification_obligations verification_obligations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.verification_obligations
    ADD CONSTRAINT verification_obligations_pkey PRIMARY KEY (obligation_id);


--
-- Name: idx_agent_choice_impacts_attempt_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_choice_impacts_attempt_position ON public.agent_choice_impacts USING btree (attempt_id, event_global_position);


--
-- Name: idx_artifact_observations_exact_locator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_artifact_observations_exact_locator ON public.development_artifact_observations USING btree (scope, source_kind, source_revision, observed_sequence);


--
-- Name: idx_attempt_histories_current_write_sets; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attempt_histories_current_write_sets ON public.attempt_histories USING btree (write_set_repository_id, write_set_expires_at_domain, attempt_id) WHERE ((write_set_lease_set_id IS NOT NULL) AND (write_set_released_at_domain IS NULL) AND (terminal_at_domain IS NULL));


--
-- Name: idx_attempt_histories_work_item_cursor; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_attempt_histories_work_item_cursor ON public.attempt_histories USING btree (work_item_id, authorized_global_position, attempt_id);


--
-- Name: idx_attempt_histories_write_set_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_attempt_histories_write_set_identity ON public.attempt_histories USING btree (write_set_lease_set_id, attempt_id) WHERE (write_set_lease_set_id IS NOT NULL);


--
-- Name: idx_candidate_changed_resources_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_candidate_changed_resources_identity ON public.candidate_changed_resources USING btree (candidate_id, path);


--
-- Name: idx_candidate_changed_resources_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_candidate_changed_resources_lookup ON public.candidate_changed_resources USING btree (change_set_id, repository_id, path, candidate_id);


--
-- Name: idx_candidate_impact_keys_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_candidate_impact_keys_identity ON public.candidate_impact_keys USING btree (candidate_id, direction, impact_key);


--
-- Name: idx_candidate_impact_keys_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_candidate_impact_keys_lookup ON public.candidate_impact_keys USING btree (change_set_id, impact_key, direction, candidate_id);


--
-- Name: idx_candidate_observed_inputs_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_candidate_observed_inputs_identity ON public.candidate_observed_inputs USING btree (candidate_id, path);


--
-- Name: idx_candidate_observed_inputs_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_candidate_observed_inputs_lookup ON public.candidate_observed_inputs USING btree (change_set_id, repository_id, path, candidate_id);


--
-- Name: idx_candidates_attempt_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_candidates_attempt_position ON public.candidates USING btree (attempt_id, submitted_global_position);


--
-- Name: idx_coordinator_context_scopes_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_coordinator_context_scopes_identity ON public.coordinator_context_scopes USING btree (scope_kind, scope_id);


--
-- Name: idx_merge_authorizations_snapshot_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_merge_authorizations_snapshot_position ON public.merge_authorizations USING btree (merge_snapshot_id, source_global_position);


--
-- Name: idx_merge_snapshots_commit_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_merge_snapshots_commit_identity ON public.merge_snapshots USING btree (repository_id, object_format, merge_commit_oid);


--
-- Name: idx_on_current_global_position_ed0086fb2b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_current_global_position_ed0086fb2b ON public.development_artifact_observations USING btree (current_global_position);


--
-- Name: idx_on_declared_global_position_66c5eb75e9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_declared_global_position_66c5eb75e9 ON public.development_artifact_relations USING btree (declared_global_position);


--
-- Name: idx_on_message_id_stream_revision_4258fdb4a5; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_message_id_stream_revision_4258fdb4a5 ON public.decision_interpretations USING btree (message_id, stream_revision);


--
-- Name: idx_on_observed_sequence_9f24f34c1e; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_observed_sequence_9f24f34c1e ON public.development_artifact_relation_supersessions USING btree (observed_sequence);


--
-- Name: idx_on_replacement_relation_id_79c802b934; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_replacement_relation_id_79c802b934 ON public.development_artifact_relation_supersessions USING btree (replacement_relation_id);


--
-- Name: idx_on_repository_id_object_format_head_commit_oid_9c83b0d102; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_repository_id_object_format_head_commit_oid_9c83b0d102 ON public.candidates USING btree (repository_id, object_format, head_commit_oid);


--
-- Name: idx_on_source_artifact_id_87bf754702; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_source_artifact_id_87bf754702 ON public.development_artifact_relation_supersessions USING btree (source_artifact_id);


--
-- Name: idx_on_superseded_global_position_379153d0e9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_superseded_global_position_379153d0e9 ON public.development_artifact_relation_supersessions USING btree (superseded_global_position);


--
-- Name: idx_on_target_kind_target_id_389d0c51da; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_target_kind_target_id_389d0c51da ON public.development_artifact_relations USING btree (target_kind, target_id);


--
-- Name: idx_processed_projection_events_command; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_processed_projection_events_command ON public.processed_projection_events USING btree (projection_name, projection_version, command_id);


--
-- Name: idx_processed_projection_events_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_processed_projection_events_identity ON public.processed_projection_events USING btree (projection_name, projection_version, stream_context, stream_name, stream_id, stream_revision);


--
-- Name: idx_resources_on_repository_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_resources_on_repository_id ON public.resources USING btree (repository_id, resource_id);


--
-- Name: idx_resources_on_repository_kind_path; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_resources_on_repository_kind_path ON public.resources USING btree (repository_id, kind, normalized_path);


--
-- Name: idx_resources_on_repository_status_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_resources_on_repository_status_id ON public.resources USING btree (repository_id, lifecycle_status, resource_id);


--
-- Name: idx_verification_evidence_event; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_verification_evidence_event ON public.verification_obligation_evidence_items USING btree (event_id);


--
-- Name: idx_verification_evidence_obligation_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_verification_evidence_obligation_digest ON public.verification_obligation_evidence_items USING btree (obligation_id, assessment_input_digest);


--
-- Name: idx_verification_evidence_obligation_revision; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_verification_evidence_obligation_revision ON public.verification_obligation_evidence_items USING btree (obligation_id, stream_revision);


--
-- Name: idx_verification_evidence_progress; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_verification_evidence_progress ON public.verification_obligation_evidence_items USING btree (obligation_id, evidence_kind, conclusion);


--
-- Name: idx_verification_obligations_change_set; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_verification_obligations_change_set ON public.verification_obligations USING btree (change_set_id, status, event_global_position);


--
-- Name: idx_verification_obligations_claim_expiry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_verification_obligations_claim_expiry ON public.verification_obligations USING btree (claim_expires_at_domain, event_global_position);


--
-- Name: idx_verification_obligations_claimant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_verification_obligations_claimant ON public.verification_obligations USING btree (claimant_id, event_global_position);


--
-- Name: idx_verification_obligations_enforcement; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_verification_obligations_enforcement ON public.verification_obligations USING btree (enforcement, event_global_position);


--
-- Name: idx_verification_obligations_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_verification_obligations_kind ON public.verification_obligations USING btree (kind, event_global_position);


--
-- Name: idx_verification_obligations_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_verification_obligations_position ON public.verification_obligations USING btree (event_global_position);


--
-- Name: idx_verification_obligations_source_candidate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_verification_obligations_source_candidate ON public.verification_obligations USING btree (source_candidate_id, event_global_position);


--
-- Name: idx_verification_obligations_source_repository; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_verification_obligations_source_repository ON public.verification_obligations USING btree (source_repository_id, event_global_position);


--
-- Name: idx_verification_obligations_source_work_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_verification_obligations_source_work_item ON public.verification_obligations USING btree (source_work_item_id, event_global_position);


--
-- Name: idx_verification_obligations_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_verification_obligations_status ON public.verification_obligations USING btree (status, event_global_position);


--
-- Name: idx_verification_obligations_target_candidate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_verification_obligations_target_candidate ON public.verification_obligations USING btree (target_candidate_id, event_global_position);


--
-- Name: idx_verification_obligations_target_repository; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_verification_obligations_target_repository ON public.verification_obligations USING btree (target_repository_id, event_global_position);


--
-- Name: idx_verification_obligations_target_work_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_verification_obligations_target_work_item ON public.verification_obligations USING btree (target_work_item_id, event_global_position);


--
-- Name: index_agent_choice_impacts_on_choice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_agent_choice_impacts_on_choice_id ON public.agent_choice_impacts USING btree (choice_id);


--
-- Name: index_agent_choice_impacts_on_outcome; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_agent_choice_impacts_on_outcome ON public.agent_choice_impacts USING btree (outcome);


--
-- Name: index_agent_choices_on_choice_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_agent_choices_on_choice_type ON public.agent_choices USING btree (choice_type);


--
-- Name: index_agent_choices_on_observation_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_agent_choices_on_observation_status ON public.agent_choices USING btree (observation_status);


--
-- Name: index_attempt_histories_on_change_set_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_attempt_histories_on_change_set_id ON public.attempt_histories USING btree (change_set_id);


--
-- Name: index_attempt_histories_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_attempt_histories_on_status ON public.attempt_histories USING btree (status);


--
-- Name: index_candidates_on_change_set_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_candidates_on_change_set_id ON public.candidates USING btree (change_set_id);


--
-- Name: index_candidates_on_work_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_candidates_on_work_item_id ON public.candidates USING btree (work_item_id);


--
-- Name: index_command_receipts_on_receipt; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_command_receipts_on_receipt ON public.command_receipts USING btree (receipt);


--
-- Name: index_coordinator_context_scopes_on_change_set_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_coordinator_context_scopes_on_change_set_id ON public.coordinator_context_scopes USING btree (change_set_id);


--
-- Name: index_decision_definitions_on_definition_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_decision_definitions_on_definition_digest ON public.decision_definitions USING btree (definition_digest);


--
-- Name: index_decision_definitions_on_interpretation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_decision_definitions_on_interpretation_id ON public.decision_definitions USING btree (interpretation_id);


--
-- Name: index_decision_definitions_on_policy_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_decision_definitions_on_policy_status ON public.decision_definitions USING btree (policy_status);


--
-- Name: index_decision_interpretations_on_clarification_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_decision_interpretations_on_clarification_event_id ON public.decision_interpretations USING btree (clarification_event_id);


--
-- Name: index_decision_interpretations_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_decision_interpretations_on_event_id ON public.decision_interpretations USING btree (event_id);


--
-- Name: index_decision_interpretations_on_lifecycle_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_decision_interpretations_on_lifecycle_status ON public.decision_interpretations USING btree (lifecycle_status);


--
-- Name: index_decision_interpretations_on_proposal_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_decision_interpretations_on_proposal_status ON public.decision_interpretations USING btree (proposal_status);


--
-- Name: index_decision_partition_heads_on_decision_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_decision_partition_heads_on_decision_id ON public.decision_partition_heads USING btree (decision_id);


--
-- Name: index_decision_partition_heads_on_partition_revision; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_decision_partition_heads_on_partition_revision ON public.decision_partition_heads USING btree (partition_revision);


--
-- Name: index_decision_slot_heads_on_decision_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_decision_slot_heads_on_decision_id ON public.decision_slot_heads USING btree (decision_id);


--
-- Name: index_development_artifact_observations_on_artifact_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_development_artifact_observations_on_artifact_id ON public.development_artifact_observations USING btree (artifact_id);


--
-- Name: index_development_artifact_observations_on_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_development_artifact_observations_on_kind ON public.development_artifact_observations USING btree (kind);


--
-- Name: index_development_artifact_observations_on_labels; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_development_artifact_observations_on_labels ON public.development_artifact_observations USING gin (labels);


--
-- Name: index_development_artifact_observations_on_observed_sequence; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_development_artifact_observations_on_observed_sequence ON public.development_artifact_observations USING btree (observed_sequence);


--
-- Name: index_development_artifact_observations_on_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_development_artifact_observations_on_scope ON public.development_artifact_observations USING btree (scope);


--
-- Name: index_development_artifact_observations_on_source_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_development_artifact_observations_on_source_kind ON public.development_artifact_observations USING btree (source_kind);


--
-- Name: index_development_artifact_observations_on_source_locator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_development_artifact_observations_on_source_locator ON public.development_artifact_observations USING hash (source_locator);


--
-- Name: index_development_artifact_relations_on_observed_sequence; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_development_artifact_relations_on_observed_sequence ON public.development_artifact_relations USING btree (observed_sequence);


--
-- Name: index_development_artifact_relations_on_source_artifact_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_development_artifact_relations_on_source_artifact_id ON public.development_artifact_relations USING btree (source_artifact_id);


--
-- Name: index_development_artifacts_on_captured_global_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_development_artifacts_on_captured_global_position ON public.development_artifacts USING btree (captured_global_position);


--
-- Name: index_development_artifacts_on_exact_locator_context; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_development_artifacts_on_exact_locator_context ON public.development_artifacts USING btree (scope, source_kind, source_revision, observed_sequence);


--
-- Name: index_development_artifacts_on_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_development_artifacts_on_kind ON public.development_artifacts USING btree (kind);


--
-- Name: index_development_artifacts_on_labels; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_development_artifacts_on_labels ON public.development_artifacts USING gin (labels);


--
-- Name: index_development_artifacts_on_observed_sequence; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_development_artifacts_on_observed_sequence ON public.development_artifacts USING btree (observed_sequence);


--
-- Name: index_development_artifacts_on_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_development_artifacts_on_scope ON public.development_artifacts USING btree (scope);


--
-- Name: index_development_artifacts_on_source_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_development_artifacts_on_source_kind ON public.development_artifacts USING btree (source_kind);


--
-- Name: index_development_artifacts_on_source_locator_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_development_artifacts_on_source_locator_hash ON public.development_artifacts USING hash (source_locator);


--
-- Name: index_merge_authorizations_on_source_global_position; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_merge_authorizations_on_source_global_position ON public.merge_authorizations USING btree (source_global_position);


--
-- Name: index_merge_snapshots_on_registered_global_position; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_merge_snapshots_on_registered_global_position ON public.merge_snapshots USING btree (registered_global_position);


--
-- Name: index_merge_snapshots_on_verification_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_merge_snapshots_on_verification_status ON public.merge_snapshots USING btree (verification_status);


--
-- Name: index_operation_batch_items_on_batch_id_and_item_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_operation_batch_items_on_batch_id_and_item_index ON public.operation_batch_items USING btree (batch_id, item_index);


--
-- Name: index_operation_batch_items_on_command_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_operation_batch_items_on_command_id ON public.operation_batch_items USING btree (command_id);


--
-- Name: index_operation_batch_outcomes_on_batch_id_and_item_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_operation_batch_outcomes_on_batch_id_and_item_index ON public.operation_batch_outcomes USING btree (batch_id, item_index);


--
-- Name: index_operation_batch_outcomes_on_outcome_global_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_operation_batch_outcomes_on_outcome_global_position ON public.operation_batch_outcomes USING btree (outcome_global_position);


--
-- Name: index_operation_batches_on_created_global_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_operation_batches_on_created_global_position ON public.operation_batches USING btree (created_global_position);


--
-- Name: index_operation_batches_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_operation_batches_on_status ON public.operation_batches USING btree (status);


--
-- Name: index_release_sets_on_change_set_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_release_sets_on_change_set_id ON public.release_sets USING btree (change_set_id);


--
-- Name: index_release_sets_on_prepared_global_position; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_release_sets_on_prepared_global_position ON public.release_sets USING btree (prepared_global_position);


--
-- Name: index_release_sets_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_release_sets_on_status ON public.release_sets USING btree (status);


--
-- Name: index_release_sets_on_verification_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_release_sets_on_verification_status ON public.release_sets USING btree (verification_status);


--
-- Name: index_repositories_on_registered_global_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_repositories_on_registered_global_position ON public.repositories USING btree (registered_global_position);


--
-- Name: index_repositories_on_scope_and_repository_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_repositories_on_scope_and_repository_id ON public.repositories USING btree (scope, repository_id);


--
-- Name: index_resources_on_latest_transition_global_position; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_resources_on_latest_transition_global_position ON public.resources USING btree (latest_transition_global_position);


--
-- Name: index_resources_on_registered_global_position; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_resources_on_registered_global_position ON public.resources USING btree (registered_global_position);


--
-- Name: index_skill_assets_on_skill_id_and_revision_and_path; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_skill_assets_on_skill_id_and_revision_and_path ON public.skill_assets USING btree (skill_id, revision, path);


--
-- Name: index_skill_revisions_on_published_global_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_skill_revisions_on_published_global_position ON public.skill_revisions USING btree (published_global_position);


--
-- Name: index_skill_revisions_on_skill_id_and_revision; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_skill_revisions_on_skill_id_and_revision ON public.skill_revisions USING btree (skill_id, revision);


--
-- Name: index_skills_on_name_and_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_skills_on_name_and_scope ON public.skills USING btree (name, scope);


--
-- Name: index_user_utterances_on_conversation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_utterances_on_conversation_id ON public.user_utterances USING btree (conversation_id);


--
-- Name: index_user_utterances_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_user_utterances_on_event_id ON public.user_utterances USING btree (event_id);


--
-- Name: operation_batch_items fk_rails_0609cbe4ba; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operation_batch_items
    ADD CONSTRAINT fk_rails_0609cbe4ba FOREIGN KEY (batch_id) REFERENCES public.operation_batches(batch_id) ON DELETE CASCADE;


--
-- Name: skill_revisions fk_rails_0dc97a2366; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_revisions
    ADD CONSTRAINT fk_rails_0dc97a2366 FOREIGN KEY (skill_id) REFERENCES public.skills(skill_id) ON DELETE CASCADE;


--
-- Name: skill_assets fk_rails_3ae5a1613c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_assets
    ADD CONSTRAINT fk_rails_3ae5a1613c FOREIGN KEY (skill_id) REFERENCES public.skills(skill_id) ON DELETE CASCADE;


--
-- Name: operation_batch_outcomes fk_rails_bc185e7de3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operation_batch_outcomes
    ADD CONSTRAINT fk_rails_bc185e7de3 FOREIGN KEY (batch_id) REFERENCES public.operation_batches(batch_id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260901063000'),
('20260831155000'),
('20260831135500'),
('20260829132000'),
('20260828104228'),
('20260828103000'),
('20260828085000'),
('20260827153000'),
('20260826151500'),
('20260826144500'),
('20260826120000'),
('20260825160000'),
('20260825143000'),
('20260825094500'),
('20260824220000'),
('20260824210000'),
('20260824182500'),
('20260824175000'),
('20260824170000'),
('20260824161000'),
('20260824152000'),
('20260824083500'),
('20260824080000'),
('20260823194000'),
('20260823162000'),
('20260823141500'),
('20260823123000'),
('20260823070000'),
('20260822223000'),
('20260822213000'),
('20260822204500'),
('20260822170000'),
('20260822160000'),
('20260822151000'),
('20260820184500');
