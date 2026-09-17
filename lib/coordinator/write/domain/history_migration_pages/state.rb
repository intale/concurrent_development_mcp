# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module HistoryMigrationPages
      class State < Value
        PLANNING_EVENT_CLASSES = [
          Events::HistoryMigrationPageCreatedV1,
          Events::HistoryMigrationPageAddedToMigrationV1,
          Events::HistoryMigrationPageSourceRangeSelectedV1,
          Events::HistoryMigrationPageSourceEventCountRecordedV1,
          Events::HistoryMigrationPageTargetEventCountRecordedV1,
          Events::HistoryMigrationPagePlannedV1
        ].freeze
        DEPENDENCY_WAVE_COUNT = Types::HISTORY_MIGRATION_DEPENDENCY_WAVE_MAXIMUM + 1
        MAXIMUM_STEP = PLANNING_EVENT_CLASSES.length + DEPENDENCY_WAVE_COUNT + 1

        attribute :step, Types::Integer.constrained(gteq: 0, lteq: MAXIMUM_STEP)
        attribute :page_id, Types::UuidV7.optional
        attribute :migration_id, Types::UuidV7.optional
        attribute :from_position, Types::GlobalPosition.optional
        attribute :to_position, Types::GlobalPosition.optional
        attribute :source_event_count, Types::HistoryMigrationSourceEventCount.optional
        attribute :target_event_count, Types::HistoryMigrationTargetEventCount.optional
        attribute :applied_wave_target_event_counts,
                  Types::Array.of(Types::HistoryMigrationWaveTargetEventCount)
                    .constrained(max_size: DEPENDENCY_WAVE_COUNT)

        def self.initial
          new(
            step: 0,
            page_id: nil,
            migration_id: nil,
            from_position: nil,
            to_position: nil,
            source_event_count: nil,
            target_event_count: nil,
            applied_wave_target_event_counts: []
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
          step >= PLANNING_EVENT_CLASSES.length
        end

        def applied?
          step == MAXIMUM_STEP
        end

        def next_dependency_wave
          applied_wave_target_event_counts.length
        end

        def dependency_wave_applied?(dependency_wave)
          dependency_wave < next_dependency_wave
        end

        def target_event_count_for(dependency_wave)
          applied_wave_target_event_counts.fetch(dependency_wave)
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
          expected = expected_event_class
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
          when Events::HistoryMigrationPageDependencyWaveAppliedV1
            unless event.dependency_wave == next_dependency_wave
              raise InvalidHistoryMigrationHistory, "HistoryMigrationPage dependency waves are not contiguous"
            end
            changes[:applied_wave_target_event_counts] = applied_wave_target_event_counts + [ event.target_event_count ]
          end

          next_state = self.class.new(attributes.merge(changes))
          if event.is_a?(Events::HistoryMigrationPageSourceEventCountRecordedV1) &&
              next_state.source_event_count > (next_state.to_position - next_state.from_position + 1)
            raise InvalidHistoryMigrationHistory, "HistoryMigrationPage count exceeds its source range"
          end
          if event.is_a?(Events::HistoryMigrationPageDependencyWaveAppliedV1) &&
              next_state.next_dependency_wave == DEPENDENCY_WAVE_COUNT &&
              next_state.applied_wave_target_event_counts.sum != next_state.target_event_count
            raise InvalidHistoryMigrationHistory, "HistoryMigrationPage applied count differs from its plan"
          end

          next_state
        end

        private

        def expected_event_class
          return PLANNING_EVENT_CLASSES[step] if step < PLANNING_EVENT_CLASSES.length
          return Events::HistoryMigrationPageDependencyWaveAppliedV1 if step < MAXIMUM_STEP - 1
          return Events::HistoryMigrationPageAppliedV1 if step == MAXIMUM_STEP - 1

          nil
        end
      end
    end
  end
end
