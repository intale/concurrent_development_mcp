# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareExpandWriteSet < Dry::Operation
      def initialize(
        contract: Contracts::ExpandWriteSet.new,
        git_object_ids_contract: Contracts::GitObjectIds.new,
        resource_normalizer: FileResourceNormalizer.new
      )
        @contract = contract
        @git_object_ids_contract = git_object_ids_contract
        @resource_normalizer = resource_normalizer
      end

      def call(input)
        attributes = step validate(input)
        step validate_object_ids(attributes)
        resources = step normalize_resources(attributes)

        step build_command(attributes, resources:)
      end

      private

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "ExpandWriteSet input is invalid",
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
            message: "Write-set expansion evidence contains an invalid Git object ID",
            details: result.errors.to_h
          )
        )
      end

      def normalize_resources(attributes)
        normalized = attributes.fetch(:resources).map do |resource|
          result = @resource_normalizer.call(
            repository_id: attributes.fetch(:repository_id),
            kind: resource.fetch(:kind),
            path: resource.fetch(:path),
            base_blob_oid: resource[:base_blob_oid]
          )
          return result if result.failure?

          result.value!
        end

        collapse_resources(normalized)
      end

      def collapse_resources(resources)
        grouped = resources.group_by(&:resource_key_hash)
        conflict = grouped.values.find { _1.map(&:base_blob_oid).uniq.length > 1 }
        if conflict
          return Failure(
            OutcomeError.new(
              code: :resource_evidence_conflict,
              message: "Duplicate resource aliases contain conflicting base evidence",
              details: { resource_key: conflict.first.resource_key }
            )
          )
        end

        Success(grouped.values.map(&:first).sort_by { _1.resource_key_hash.b })
      end

      def build_command(attributes, resources:)
        actor_attributes = attributes.fetch(:actor)

        Success(
          Commands::ExpandWriteSet.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(
              kind: actor_attributes.fetch(:kind),
              id: actor_attributes.fetch(:id)
            ),
            change_set_id: attributes.fetch(:change_set_id),
            work_item_id: attributes.fetch(:work_item_id),
            attempt_id: attributes.fetch(:attempt_id),
            lease_set_id: attributes.fetch(:lease_set_id),
            repository_id: attributes.fetch(:repository_id),
            base_commit_oid: attributes.fetch(:base_commit_oid),
            resources:
          )
        )
      end
    end
  end
end
