# frozen_string_literal: true

module Coordinator::Write
  class CommandInputDigest
    def initialize(canonical_json: CanonicalJson.new)
      @canonical_json = canonical_json
    end

    def call(command)
      @canonical_json.sha256(document(command).to_h)
    end

    def document(command)
      case command
      when Commands::CreateChangeSet then create_change_set_document(command)
      when Commands::CreateWorkItem then work_item_create_document(command)
      when Commands::DeclareWorkItemDependency then work_item_dependency_declare_document(command)
      when Commands::ActivateChangeSet then change_set_activate_document(command)
      when Commands::AcquireWorkItem then work_item_acquire_document(command)
      when Commands::ReserveWriteSet then write_set_reserve_document(command)
      when Commands::ExpandWriteSet then write_set_expand_document(command)
      when Commands::RenewLeaseSet then lease_renew_document(command)
      else
        raise ArgumentError, "Unsupported coordination command: #{command.class.name}"
      end
    end

    def create_change_set(command)
      @canonical_json.sha256(create_change_set_document(command).to_h)
    end

    def create_change_set_document(command)
      CommandInputDocuments::CreateChangeSetV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "change_set_create",
        input: CommandInputDocuments::CreateChangeSetInputV1.new(
          actor: actor_document(command.actor),
          change_set_id: command.change_set_id,
          goal: command.goal,
          acceptance_criteria: command.acceptance_criteria
        )
      )
    end

    def work_item_create(command)
      @canonical_json.sha256(work_item_create_document(command).to_h)
    end

    def work_item_create_document(command)
      CommandInputDocuments::CreateWorkItemV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "work_item_create",
        input: CommandInputDocuments::CreateWorkItemInputV1.new(
          actor: actor_document(command.actor),
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          repository_id: command.repository_id,
          goal: command.goal,
          acceptance_criteria: command.acceptance_criteria
        )
      )
    end

    def work_item_dependency_declare(command)
      @canonical_json.sha256(work_item_dependency_declare_document(command).to_h)
    end

    def work_item_dependency_declare_document(command)
      CommandInputDocuments::DeclareWorkItemDependencyV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "work_item_dependency_declare",
        input: CommandInputDocuments::DeclareWorkItemDependencyInputV1.new(
          actor: actor_document(command.actor),
          change_set_id: command.change_set_id,
          dependency_id: command.dependency_id,
          producer_work_item_id: command.producer_work_item_id,
          consumer_work_item_id: command.consumer_work_item_id,
          dependency_kind: command.dependency_kind,
          required_output: command.required_output
        )
      )
    end

    def change_set_activate(command)
      @canonical_json.sha256(change_set_activate_document(command).to_h)
    end

    def change_set_activate_document(command)
      CommandInputDocuments::ActivateChangeSetV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "change_set_activate",
        input: CommandInputDocuments::ActivateChangeSetInputV1.new(
          actor: actor_document(command.actor),
          change_set_id: command.change_set_id
        )
      )
    end

    def work_item_acquire(command)
      @canonical_json.sha256(work_item_acquire_document(command).to_h)
    end

    def work_item_acquire_document(command)
      CommandInputDocuments::AcquireWorkItemV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "work_item_acquire",
        input: CommandInputDocuments::AcquireWorkItemInputV1.new(
          actor: actor_document(command.actor),
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          base_snapshots: command.base_snapshots.map do |snapshot|
            CommandInputDocuments::RepositorySnapshotV1.new(snapshot.to_h)
          end
        )
      )
    end

    def write_set_reserve(command)
      @canonical_json.sha256(write_set_reserve_document(command).to_h)
    end

    def write_set_reserve_document(command)
      CommandInputDocuments::ReserveWriteSetV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "write_set_reserve",
        input: CommandInputDocuments::ReserveWriteSetInputV1.new(
          actor: actor_document(command.actor),
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          repository_id: command.repository_id,
          base_commit_oid: command.base_commit_oid,
          resources: command.resources.map do |resource|
            CommandInputDocuments::FileResourceV1.new(resource.to_h)
          end,
          lease_duration_seconds: command.lease_duration_seconds
        )
      )
    end

    def write_set_expand(command)
      @canonical_json.sha256(write_set_expand_document(command).to_h)
    end

    def write_set_expand_document(command)
      CommandInputDocuments::ExpandWriteSetV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "write_set_expand",
        input: CommandInputDocuments::ExpandWriteSetInputV1.new(
          actor: actor_document(command.actor),
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          lease_set_id: command.lease_set_id,
          repository_id: command.repository_id,
          base_commit_oid: command.base_commit_oid,
          resources: command.resources.map do |resource|
            CommandInputDocuments::FileResourceV1.new(resource.to_h)
          end
        )
      )
    end

    def lease_renew(command)
      @canonical_json.sha256(lease_renew_document(command).to_h)
    end

    def lease_renew_document(command)
      CommandInputDocuments::RenewLeaseSetV1.new(
        schema: "command-input/v1",
        command_id: command.command_id,
        tool_name: "lease_renew",
        input: CommandInputDocuments::RenewLeaseSetInputV1.new(
          actor: actor_document(command.actor),
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          lease_set_id: command.lease_set_id,
          leases: command.leases.map do |reference|
            CommandInputDocuments::LeaseRenewalReferenceV1.new(reference.to_h)
          end,
          lease_duration_seconds: command.lease_duration_seconds
        )
      )
    end

    private

    def actor_document(actor)
      CommandInputDocuments::ActorV1.new(
        actor_kind: actor.kind,
        actor_id: actor.id
      )
    end
  end
end
