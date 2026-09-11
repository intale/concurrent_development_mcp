# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ChangeSets
      class Complete
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, work_items:, release_state:, command:, completed_at:)
          denial = denied(state:, work_items:, release_state:, command:)
          return denial if denial

          stream = @stream_factory.change_set(command.change_set_id)
          writes = []
          if command.release_set_id
            writes << EventWrite.new(
              stream:,
              event: Events::ChangeSetReleaseSetLinkedV1.new(
                change_set_id: command.change_set_id,
                release_set_id: command.release_set_id
              )
            )
          end
          writes << EventWrite.new(
            stream:,
            event: Events::ChangeSetCompletedV2.new(change_set_id: command.change_set_id)
          )
          Success(EventPlan.new(writes:))
        end

        private

        def denied(state:, work_items:, release_state:, command:)
          return failure(:change_set_not_found, "ChangeSet does not exist", command) if state.absent?
          return failure(:change_set_already_completed, "ChangeSet is already completed", command) if state.status == "completed"
          return failure(:change_set_not_active, "ChangeSet is not active", command) unless state.status == "active"
          return failure(:work_item_incomplete, "Every frozen ChangeSet WorkItem must be completed", command) unless complete_members?(state, work_items)

          unsatisfied = state.dependencies.find { !state.dependency_satisfied?(_1.dependency_id) }
          if unsatisfied
            return failure(
              :dependency_unsatisfied,
              "Every frozen ChangeSet dependency must be satisfied",
              command,
              dependency_id: unsatisfied.dependency_id
            )
          end

          return nil if work_items.map(&:repository_id).uniq.one?
          return failure(:release_required, "A multi-repository ChangeSet requires a completed ReleaseSet", command) unless release_state
          return failure(:release_not_activated, "ReleaseSet did not complete with the activated outcome", command) unless activated_release?(release_state)
          return failure(:release_change_set_mismatch, "ReleaseSet belongs to another ChangeSet", command) unless release_change_set_matches?(release_state, command)
          return failure(:release_coverage_mismatch, "ReleaseSet does not exactly cover completed WorkItem results", command) unless exact_coverage?(release_state, work_items)

          nil
        end

        def complete_members?(state, work_items)
          state.work_item_ids == work_items.map(&:work_item_id) &&
            work_items.all? { _1.change_set_id == state.change_set_id }
        end

        def activated_release?(release_state)
          release_state.preparation && release_state.activation && release_state.completion &&
            release_state.completion.payload.outcome == "activated" &&
            release_state.preparation.payload.release_digest == release_state.activation.release_digest &&
            release_state.activation.release_digest == release_state.completion.release_digest
        end

        def release_change_set_matches?(release_state, command)
          [
            release_state.preparation.payload.change_set_id,
            release_state.activation.payload.change_set_id
          ].uniq == [ command.change_set_id ] &&
            release_state.preparation.payload.release_set_id == command.release_set_id &&
            release_state.activation.payload.release_set_id == command.release_set_id &&
            release_state.completion.payload.release_set_id == command.release_set_id
        end

        def exact_coverage?(release_state, work_items)
          expected = work_items.map { completion_key(_1) }.sort_by { |entry| entry.take(4) }
          observed = release_state.preparation.payload.ordered_members.flat_map do |member|
            member.ordered_candidates.map do |candidate|
              [
                member.repository_id,
                candidate.work_item_id,
                candidate.attempt_id,
                candidate.candidate_id,
                candidate.submission_event.to_h
              ]
            end
          end.sort_by { |entry| entry.take(4) }
          expected == observed
        end

        def completion_key(evidence)
          [
            evidence.repository_id,
            evidence.work_item_id,
            evidence.attempt_id,
            evidence.candidate_id,
            evidence.candidate_event.to_h
          ]
        end

        def failure(code, message, command, details = {})
          Failure(
            OutcomeError.new(
              code:,
              message:,
              details: { change_set_id: command.change_set_id }.merge(details)
            )
          )
        end
      end
    end
  end
end
