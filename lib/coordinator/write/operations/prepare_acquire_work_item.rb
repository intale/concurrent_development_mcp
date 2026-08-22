# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareAcquireWorkItem < Dry::Operation
      def initialize(
        contract: Contracts::AcquireWorkItem.new,
        git_object_ids_contract: Contracts::GitObjectIds.new
      )
        @contract = contract
        @git_object_ids_contract = git_object_ids_contract
      end

      def call(input)
        attributes = step validate(input)
        snapshots = step build_snapshots(attributes.fetch(:base_snapshots))

        step build_command(attributes, snapshots:)
      end

      private

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "AcquireWorkItem input is invalid",
            details: result.errors.to_h
          )
        )
      end

      def build_snapshots(attributes)
        result = @git_object_ids_contract.call(
          commit_oids: attributes.map { _1.fetch(:commit_oid) }
        )
        unless result.success?
          return Failure(
            OutcomeError.new(
              code: :invalid_git_oid,
              message: "Repository base contains an invalid Git object ID",
              details: result.errors.to_h
            )
          )
        end

        Success(
          attributes.map do |snapshot|
            commit_oid = snapshot.fetch(:commit_oid)
            RepositorySnapshotV1.new(
              repository_id: snapshot.fetch(:repository_id),
              object_format: commit_oid.length == 40 ? "sha1" : "sha256",
              commit_oid:
            )
          end
        )
      end

      def build_command(attributes, snapshots:)
        actor_attributes = attributes.fetch(:actor)

        Success(
          Commands::AcquireWorkItem.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(
              kind: actor_attributes.fetch(:kind),
              id: actor_attributes.fetch(:id)
            ),
            change_set_id: attributes.fetch(:change_set_id),
            work_item_id: attributes.fetch(:work_item_id),
            attempt_id: attributes.fetch(:attempt_id),
            base_snapshots: snapshots
          )
        )
      end
    end
  end
end
