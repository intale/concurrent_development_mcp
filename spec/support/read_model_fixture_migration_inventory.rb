# frozen_string_literal: true

module ReadModelFixtureMigrationInventory
  FACTORY_BACKED_READ_SPECS = %w[
    spec/lib/coordinator/read/queries/agent_choice_get_spec.rb
    spec/lib/coordinator/read/queries/agent_choice_impact_list_spec.rb
    spec/lib/coordinator/read/queries/candidate_get_spec.rb
    spec/lib/coordinator/read/queries/candidate_impact_get_spec.rb
    spec/lib/coordinator/read/queries/candidate_list_spec.rb
    spec/lib/coordinator/read/queries/coord_context_spec.rb
    spec/lib/coordinator/read/queries/coordination_list_spec.rb
    spec/lib/coordinator/read/queries/decision_get_spec.rb
    spec/lib/coordinator/read/queries/decision_interpretation_list_spec.rb
    spec/lib/coordinator/read/queries/decision_list_spec.rb
    spec/lib/coordinator/read/queries/decision_resolve_spec.rb
    spec/lib/coordinator/read/queries/development_artifacts_spec.rb
    spec/lib/coordinator/read/queries/guidance_get_spec.rb
    spec/lib/coordinator/read/queries/operation_batch_get_spec.rb
    spec/lib/coordinator/read/queries/operation_get_spec.rb
    spec/lib/coordinator/read/queries/repository_list_spec.rb
    spec/lib/coordinator/read/queries/resources_spec.rb
    spec/lib/coordinator/read/queries/skill_asset_get_spec.rb
    spec/lib/coordinator/read/queries/skill_get_spec.rb
    spec/lib/coordinator/read/queries/skill_list_spec.rb
    spec/lib/coordinator/read/queries/verification_obligations_list_spec.rb
  ].freeze

  DIRECT_EVENT_PROJECTOR_SPECS = %w[
    spec/lib/coordinator/read/projectors/agent_choice_impacts_v1_spec.rb
    spec/lib/coordinator/read/projectors/agent_choices_v1_spec.rb
    spec/lib/coordinator/read/projectors/candidates_v1_spec.rb
    spec/lib/coordinator/read/projectors/coord_context_v1_spec.rb
    spec/lib/coordinator/read/projectors/decision_governance_v1_spec.rb
    spec/lib/coordinator/read/projectors/decision_interpretations_v1_spec.rb
    spec/lib/coordinator/read/projectors/development_artifacts_v1_spec.rb
    spec/lib/coordinator/read/projectors/merge_snapshots_v1_spec.rb
    spec/lib/coordinator/read/projectors/operation_batches_v2_spec.rb
    spec/lib/coordinator/read/projectors/release_sets_v1_spec.rb
    spec/lib/coordinator/read/projectors/repositories_v1_spec.rb
    spec/lib/coordinator/read/projectors/resources_v1_spec.rb
    spec/lib/coordinator/read/projectors/skills_v1_spec.rb
    spec/lib/coordinator/read/projectors/user_utterances_v1_spec.rb
    spec/lib/coordinator/read/projectors/verification_obligations_v1_spec.rb
  ].freeze

  SPLIT_TRANSPORT_SPECS = %w[
    spec/requests/mcp_agent_choice_impact_spec.rb
    spec/requests/mcp_agent_choice_spec.rb
    spec/requests/mcp_candidate_impact_spec.rb
    spec/requests/mcp_candidate_spec.rb
    spec/requests/mcp_decision_activation_spec.rb
    spec/requests/mcp_decision_correction_spec.rb
    spec/requests/mcp_decision_interpretation_spec.rb
    spec/requests/mcp_decision_resolution_spec.rb
    spec/requests/mcp_development_artifacts_spec.rb
    spec/requests/mcp_guidance_spec.rb
    spec/requests/mcp_operation_batch_spec.rb
    spec/requests/mcp_verification_obligations_spec.rb
    spec/requests/mcp_walking_slice_spec.rb
  ].freeze

  SUBSCRIPTION_CONTRACT_SPECS = %w[
    spec/lib/coordinator/read/subscriptions/read_model_set_spec.rb
  ].freeze

  BY_TARGET_BOUNDARY = {
    factory_bot_read: FACTORY_BACKED_READ_SPECS,
    direct_event_projector: DIRECT_EVENT_PROJECTOR_SPECS,
    split_transport: SPLIT_TRANSPORT_SPECS,
    subscription_contract_with_cucumber_delivery: SUBSCRIPTION_CONTRACT_SPECS
  }.freeze

  ALL = BY_TARGET_BOUNDARY.values.flatten.freeze
  # These projectors reconstruct a current projection from concrete facts in
  # several streams. Their source/envelope fixtures use the real event store,
  # not commands, subscriptions or a full write-to-read fixture journey.
  PERSISTED_SOURCE_PROJECTOR_SPECS = %w[
    spec/lib/coordinator/read/projectors/coord_context_v1_spec.rb
    spec/lib/coordinator/read/projectors/development_artifacts_v1_spec.rb
    spec/lib/coordinator/read/projectors/skills_v1_spec.rb
  ].freeze
end
