# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ReleaseSets
      class Prepare
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          denial = denied(state)
          return denial if denial

          change_set_id = state.ordered_members.map(&:change_set_id).uniq.sole
          stream = @stream_factory.release_set(command.release_set_id)
          writes = [
            EventWrite.new(
              stream:,
              event: Events::ReleaseSetCreatedV1.new(
                release_set_id: command.release_set_id,
                change_set_id:
              )
            )
          ]
          state.ordered_members.each do |member|
            writes << EventWrite.new(
              stream:,
              event: Events::ReleaseSetMemberAddedV1.new(
                release_set_id: command.release_set_id,
                member_position: member.position,
                repository_id: member.repository_id,
                merge_snapshot_id: member.merge_snapshot_id,
                ordered_candidate_ids: member.ordered_candidates.map(&:candidate_id),
                authorization_event: member.authorization_event
              )
            )
          end
          writes << EventWrite.new(
            stream:,
            event: Events::ReleaseSetPreparedV2.new(
              release_set_id: command.release_set_id
            )
          )
          writes << EventWrite.new(
            stream: @stream_factory.change_set(change_set_id),
            event: Events::ChangeSetReleaseSetLinkedV1.new(
              change_set_id:,
              release_set_id: command.release_set_id
            )
          )
          Success(EventPlan.new(writes:))
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
