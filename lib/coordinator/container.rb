# frozen_string_literal: true

module Coordinator
  class Container < Dry::System::Container
    register("canonical_json", memoize: true) { Shared::CanonicalJson.new }
    register("compound_marker_builder", memoize: true) do
      Shared::CompoundMarkerBuilder.new(canonical_json: self["canonical_json"])
    end
    register("clock", memoize: true) { Shared::SystemClock.new }
    register("id_generator", memoize: true) { Shared::IdGenerator.new }
    register("stream_factory", memoize: true) { Write::StreamFactory.new }
    register("event_schema_registry", memoize: true) { Write::EventSchemaRegistry.new }

    register("event_factory", memoize: true) do
      Write::EventFactory.new(registry: self["event_schema_registry"])
    end

    register("command_input_digest", memoize: true) do
      Write::CommandInputDigest.new(canonical_json: self["canonical_json"])
    end

    register("command_completion_builder", memoize: true) do
      Write::CommandCompletionBuilder.new
    end

    register("operations.prepare_create_change_set", memoize: true) do
      Write::Operations::PrepareCreateChangeSet.new
    end

    register("operations.prepare_create_work_item", memoize: true) do
      Write::Operations::PrepareCreateWorkItem.new
    end

    register("operations.prepare_declare_work_item_dependency", memoize: true) do
      Write::Operations::PrepareDeclareWorkItemDependency.new
    end

    register("operations.prepare_activate_change_set", memoize: true) do
      Write::Operations::PrepareActivateChangeSet.new
    end

    register("operations.prepare_acquire_work_item", memoize: true) do
      Write::Operations::PrepareAcquireWorkItem.new
    end

    register("domain.change_sets.create", memoize: true) do
      Write::Domain::ChangeSets::Create.new(stream_factory: self["stream_factory"])
    end

    register("domain.work_items.create", memoize: true) do
      Write::Domain::WorkItems::Create.new(stream_factory: self["stream_factory"])
    end

    register("domain.change_sets.declare_work_item_dependency", memoize: true) do
      Write::Domain::ChangeSets::DeclareWorkItemDependency.new(stream_factory: self["stream_factory"])
    end

    register("domain.change_sets.activate", memoize: true) do
      Write::Domain::ChangeSets::Activate.new(stream_factory: self["stream_factory"])
    end

    register("domain.work_items.evaluate_readiness", memoize: true) do
      Write::Domain::WorkItems::EvaluateReadiness.new(stream_factory: self["stream_factory"])
    end

    register("domain.work_items.acquire", memoize: true) do
      Write::Domain::WorkItems::Acquire.new(stream_factory: self["stream_factory"])
    end

    register("change_set_activation_source_builder", memoize: true) do
      Processes::ChangeSetActivationSourceBuilder.new(schema_registry: self["event_schema_registry"])
    end

    register("readiness_command_builder", memoize: true) do
      Processes::ReadinessCommandBuilder.new(compound_marker_builder: self["compound_marker_builder"])
    end

    register("readiness_targets_builder", memoize: true) { Processes::ReadinessTargetsBuilder.new }

    register("event_store", memoize: true) do
      Write::EventStore.new(client: PgEventstore.client)
    end

    register("repositories.processed_projection_events", memoize: true) do
      Read::Repositories::ProcessedProjectionEvents.new
    end

    register("repositories.command_receipts", memoize: true) do
      Read::Repositories::CommandReceipts.new(schema_registry: self["event_schema_registry"])
    end

    register("repositories.coord_contexts", memoize: true) do
      Read::Repositories::CoordContexts.new
    end

    register("projectors.coord_context_v1", memoize: true) do
      Read::Projectors::CoordContextV1.new(
        schema_registry: self["event_schema_registry"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.command_receipts_v1", memoize: true) do
      Read::Projectors::CommandReceiptsV1.new(
        schema_registry: self["event_schema_registry"],
        receipts: self["repositories.command_receipts"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("command_completion_lookup", memoize: true) do
      Read::CommandCompletionLookup.new(
        receipts: self["repositories.command_receipts"]
      )
    end

    register("queries.operation_get") do
      Read::Queries::OperationGet.new(
        completions: self["command_completion_lookup"]
      )
    end

    register("queries.coord_context") do
      Read::Queries::CoordContext.new(
        contexts: self["repositories.coord_contexts"],
        canonical_json: self["canonical_json"]
      )
    end

    register("mcp.settings", memoize: true) { Mcp::SettingsLoader.new.call }
    register("mcp.server", memoize: true) { Mcp::ServerFactory.new.call }
    register("mcp.transport", memoize: true) do
      Mcp::TransportFactory.new.call(
        server: self["mcp.server"],
        settings: self["mcp.settings"]
      )
    end

    register("operations.execute_create_change_set") do
      Write::Operations::ExecuteCreateChangeSet.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_create_change_set"],
        decider: self["domain.change_sets.create"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end


    register("operations.execute_create_work_item") do
      Write::Operations::ExecuteCreateWorkItem.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_create_work_item"],
        decider: self["domain.work_items.create"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end


    register("operations.execute_declare_work_item_dependency") do
      Write::Operations::ExecuteDeclareWorkItemDependency.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_declare_work_item_dependency"],
        decider: self["domain.change_sets.declare_work_item_dependency"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_activate_change_set") do
      Write::Operations::ExecuteActivateChangeSet.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_activate_change_set"],
        decider: self["domain.change_sets.activate"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_evaluate_work_item_readiness") do
      Write::Operations::ExecuteEvaluateWorkItemReadiness.new(
        event_store: self["event_store"],
        decider: self["domain.work_items.evaluate_readiness"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_acquire_work_item") do
      Write::Operations::ExecuteAcquireWorkItem.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_acquire_work_item"],
        decider: self["domain.work_items.acquire"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end


    register("process_managers.change_set_readiness", memoize: true) do
      Processes::ProcessManagers::ChangeSetReadiness.new(
        event_store: self["event_store"],
        source_builder: self["change_set_activation_source_builder"],
        targets_builder: self["readiness_targets_builder"],
        command_builder: self["readiness_command_builder"],
        operation: self["operations.execute_evaluate_work_item_readiness"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"]
      )
    end

    register("subscriptions.change_set_readiness", memoize: true) do
      Processes::Subscriptions::ChangeSetReadiness.new(handler: self["process_managers.change_set_readiness"])
    end

    register("subscriptions.coord_context", memoize: true) do
      Read::Subscriptions::CoordContext.new(handler: self["projectors.coord_context_v1"])
    end

    register("subscriptions.command_receipts", memoize: true) do
      Read::Subscriptions::CommandReceipts.new(handler: self["projectors.command_receipts_v1"])
    end

    register("subscription_managers.process_managers", memoize: true) do
      PgEventstore.subscriptions_manager(
        subscription_set: Processes::Subscriptions::ProcessManagerSet::SET_NAME
      )
    end

    register("subscription_sets.process_managers", memoize: true) do
      Processes::Subscriptions::ProcessManagerSet.new(
        manager: self["subscription_managers.process_managers"],
        registrations: [ self["subscriptions.change_set_readiness"] ]
      )
    end


    register("subscription_managers.read_models", memoize: true) do
      PgEventstore.subscriptions_manager(
        subscription_set: Read::Subscriptions::ReadModelSet::SET_NAME
      )
    end

    register("subscription_sets.read_models", memoize: true) do
      Read::Subscriptions::ReadModelSet.new(
        manager: self["subscription_managers.read_models"],
        registrations: [
          self["subscriptions.coord_context"],
          self["subscriptions.command_receipts"]
        ]
      )
    end
  end

  Import = Dry::AutoInject(Container)
end
