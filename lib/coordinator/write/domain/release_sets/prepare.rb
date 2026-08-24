# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ReleaseSets
      class Prepare
        include Dry::Monads[:result]

        def initialize(
          stream_factory: StreamFactory.new,
          digest_builder: Coordinator::Write::ReleaseSets::ReleaseDigestBuilder.new
        )
          @stream_factory = stream_factory
          @digest_builder = digest_builder
        end

        def call(state:, command:, prepared_at:)
          denial = denied(state)
          return denial if denial

          change_set_id = state.ordered_members.map(&:change_set_id).uniq.sole
          release_digest = @digest_builder.call(
            release_set_id: command.release_set_id,
            change_set_id:,
            ordered_members: state.ordered_members,
            policy_version: command.policy_version
          )
          event = Events::ReleaseSetPreparedV1.new(
            release_set_id: command.release_set_id,
            change_set_id:,
            ordered_members: state.ordered_members,
            release_digest:,
            policy_version: command.policy_version,
            prepared_at:
          )
          Success(
            EventPlan.new(
              writes: [ EventWrite.new(stream: @stream_factory.release_set(command.release_set_id), event:) ]
            )
          )
        end

        private

        def denied(state)
          if state.existing_preparation
            return Failure(
              OutcomeError.new(
                code: :release_set_id_already_used,
                message: "ReleaseSet ID is already prepared",
                details: { existing_event: state.existing_preparation.to_h }
              )
            )
          end

          members = state.ordered_members
          return invariant(:release_set_repositories_repeated, "ReleaseSet repositories must be unique") unless members.map(&:repository_id).uniq.length == members.length
          return invariant(:release_set_snapshots_repeated, "ReleaseSet snapshots must be unique") unless members.map(&:merge_snapshot_id).uniq.length == members.length
          return invariant(:release_set_change_sets_mixed, "ReleaseSet members must belong to one ChangeSet") unless members.map(&:change_set_id).uniq.one?

          nil
        end

        def invariant(code, message)
          Failure(OutcomeError.new(code:, message:, details: {}))
        end
      end
    end
  end
end
