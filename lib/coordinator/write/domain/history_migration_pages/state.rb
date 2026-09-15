# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module HistoryMigrationPages
      class State < Value
        EVENT_CLASSES = [
          Events::HistoryMigrationPageCreatedV1,
          Events::HistoryMigrationPageAddedToMigrationV1,
          Events::HistoryMigrationPageSourceRangeSelectedV1,
          Events::HistoryMigrationPageSourceEventCountRecordedV1,
          Events::HistoryMigrationPageTargetEventCountRecordedV1,
          Events::HistoryMigrationPagePlannedV1,
          Events::HistoryMigrationPageAppliedV1
        ].freeze

        attribute :step, Types::Integer.constrained(gteq: 0, lteq: EVENT_CLASSES.length)
        attribute :page_id, Types::UuidV7.optional
        attribute :migration_id, Types::UuidV7.optional
        attribute :from_position, Types::GlobalPosition.optional
        attribute :to_position, Types::GlobalPosition.optional
        attribute :source_event_count, Types::HistoryMigrationSourceEventCount.optional
        attribute :target_event_count, Types::HistoryMigrationTargetEventCount.optional

        def self.initial
          new(
            step: 0,
            page_id: nil,
            migration_id: nil,
            from_position: nil,
            to_position: nil,
            source_event_count: nil,
            target_event_count: nil
          )
        end

        def self.reduce(events)
          events.reduce(initial) { |state, event| state.apply(event) }
        end

        def absent?
          step.zero?
        end

        def created?
          step == 4
        end

        def planned?
          step == 6
        end

        def applied?
          step == EVENT_CLASSES.length
        end

        def matches_creation?(command)
          step >= 4 &&
            page_id == command.page_id &&
            migration_id == command.migration_id &&
            from_position == command.from_position &&
            to_position == command.to_position &&
            source_event_count == command.source_event_count
        end

        def apply(event)
          expected = EVENT_CLASSES[step]
          unless expected && event.is_a?(expected)
            raise InvalidHistoryMigrationHistory,
                  "Expected #{expected&.name || 'no further page event'}, got #{event.class.name}"
          end
          if page_id && page_id != event.page_id
            raise InvalidHistoryMigrationHistory, "HistoryMigrationPage facts disagree on page_id"
          end

          changes = { step: step + 1, page_id: event.page_id }
          case event
          when Events::HistoryMigrationPageAddedToMigrationV1
            changes[:migration_id] = event.migration_id
          when Events::HistoryMigrationPageSourceRangeSelectedV1
            changes[:from_position] = event.from_position
            changes[:to_position] = event.to_position
          when Events::HistoryMigrationPageSourceEventCountRecordedV1
            changes[:source_event_count] = event.source_event_count
          when Events::HistoryMigrationPageTargetEventCountRecordedV1
            changes[:target_event_count] = event.target_event_count
          end

          next_state = self.class.new(attributes.merge(changes))
          if event.is_a?(Events::HistoryMigrationPageSourceEventCountRecordedV1) &&
              next_state.source_event_count > (next_state.to_position - next_state.from_position + 1)
            raise InvalidHistoryMigrationHistory, "HistoryMigrationPage count exceeds its source range"
          end

          next_state
        end
      end
    end
  end
end
