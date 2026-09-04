# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module WorkIntentions
      class SetState < Value
        Reference = Types.Instance(WorkIntentionReferenceV1)

        attribute :set_id, Types::UuidV7.optional
        attribute :attempt_id, Types::Identifier.optional
        attribute :work_item_id, Types::Identifier.optional
        attribute :change_set_id, Types::Identifier.optional
        attribute :repository_id, Types::RepositoryId.optional
        attribute :members, Types::Array.of(Reference).constrained(max_size: WorkIntentionPolicyV1::MAXIMUM_SET_SIZE)

        def self.initial
          new(
            set_id: nil,
            attempt_id: nil,
            work_item_id: nil,
            change_set_id: nil,
            repository_id: nil,
            members: []
          )
        end

        def self.reduce(events)
          events.reduce(initial) { |state, event| state.apply(event) }
        end

        def absent?
          set_id.nil?
        end

        def apply(event)
          case event
          when Events::WorkIntentionSetCreatedV1
            rebuild(
              set_id: event.set_id,
              attempt_id: event.attempt_id,
              work_item_id: event.work_item_id,
              change_set_id: event.change_set_id,
              repository_id: event.repository_id
            )
          when Events::WorkIntentionAddedToSetV1
            reference = WorkIntentionReferenceV1.new(
              intention_id: event.intention_id,
              resource_id: event.resource_id
            )
            rebuild(members: members + [ reference ])
          else
            self
          end
        end

        private

        def rebuild(**changes)
          self.class.new(attributes.merge(changes))
        end
      end
    end
  end
end
