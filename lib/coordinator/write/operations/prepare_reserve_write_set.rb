# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareReserveWriteSet < Dry::Operation
      def initialize(
        contract: Contracts::ReserveWriteSet.new,
        git_object_ids_contract: Contracts::GitObjectIds.new
      )
        @contract = contract
        @git_object_ids_contract = git_object_ids_contract
      end

      def call(input)
        attributes = step validate(input)
        step validate_object_ids(attributes)
        resources = step build_resources(attributes)

        step build_command(attributes, resources:)
      end

      private

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "DeclareWorkIntentionSet input is invalid",
            details: result.errors.to_h
          )
        )
      end

      def validate_object_ids(attributes)
        resources = attributes.fetch(:resources)
        object_ids = [ attributes.fetch(:base_commit_oid) ] + resources.filter_map { _1[:base_blob_oid] }
        result = @git_object_ids_contract.call(commit_oids: object_ids)
        return Success() if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_git_oid,
            message: "Work-intention base evidence contains an invalid Git object ID",
            details: result.errors.to_h
          )
        )
      end

      def build_resources(attributes)
        resources = attributes.fetch(:resources).map do |resource|
          ResourceLeaseTargetV1.new(
            resource_id: resource.fetch(:resource_id),
            base_blob_oid: resource[:base_blob_oid],
            mode: resource.fetch(:mode, "shared"),
            purpose: resource.fetch(
              :purpose,
              "Work on WorkItem #{attributes.fetch(:work_item_id)}"
            ),
            context: resource[:context]
          )
        end

        collapse_resources(resources, attributes:)
      end

      def collapse_resources(resources, attributes:)
        grouped = resources.group_by(&:resource_id)
        conflict = grouped.values.find { _1.map(&:base_blob_oid).uniq.length > 1 }
        if conflict
          return Failure(
            OutcomeError.new(
              code: :resource_evidence_conflict,
              message: "Duplicate Resource references contain conflicting base evidence",
              details: {
                change_set_id: attributes.fetch(:change_set_id),
                work_item_id: attributes.fetch(:work_item_id),
                attempt_id: attributes.fetch(:attempt_id),
                resource_id: conflict.first.resource_id,
                current_base_blob_oid: conflict.first.base_blob_oid,
                requested_base_blob_oid: conflict.last.base_blob_oid
              }
            )
          )
        end

        Success(grouped.values.map(&:first).sort_by { _1.resource_id.b })
      end

      def build_command(attributes, resources:)
        actor_attributes = attributes.fetch(:actor)

        Success(
          Commands::ReserveWriteSet.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(
              kind: actor_attributes.fetch(:kind),
              id: actor_attributes.fetch(:id)
            ),
            change_set_id: attributes.fetch(:change_set_id),
            work_item_id: attributes.fetch(:work_item_id),
            attempt_id: attributes.fetch(:attempt_id),
            repository_id: attributes.fetch(:repository_id),
            base_commit_oid: attributes.fetch(:base_commit_oid),
            resources:,
            lease_duration_seconds: attributes.fetch(:ttl_seconds)
          )
        )
      end
    end
  end
end
