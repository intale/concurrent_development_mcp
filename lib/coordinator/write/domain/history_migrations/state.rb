# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module HistoryMigrations
      class State < Value
        EVENT_CLASSES = [
          Events::HistoryMigrationCreatedV1,
          Events::HistoryMigrationSourceStoreSelectedV1,
          Events::HistoryMigrationTargetStoreSelectedV1,
          Events::HistoryMigrationSourceRangeFrozenV1,
          Events::HistoryMigrationPageSizeSelectedV1,
          Events::HistoryMigrationStartedV1
        ].freeze

        attribute :step, Types::Integer.constrained(gteq: 0, lteq: EVENT_CLASSES.length)
        attribute :migration_id, Types::UuidV7.optional
        attribute :source_config_name, Types::Identifier.optional
        attribute :target_config_name, Types::Identifier.optional
        attribute :source_upper_position, Types::GlobalPosition.optional
        attribute :page_size, Types::HistoryMigrationPageSize.optional
        attribute :source_after_position, Types::GlobalPosition.optional.default(nil)
        attribute :source_command_ids, Types::Array.of(Types::UuidV7).constrained(max_size: 100).default([].freeze)

        def self.initial
          new(
            step: 0,
            migration_id: nil,
            source_config_name: nil,
            target_config_name: nil,
            source_upper_position: nil,
            page_size: nil
          )
        end

        def self.reduce(events)
          events.reduce(initial) { |state, event| state.apply(event) }
        end

        def absent?
          step.zero?
        end

        def started?
          step == EVENT_CLASSES.length
        end

        def matches?(command)
          started? &&
            migration_id == command.migration_id &&
            source_config_name == command.source_config_name &&
            target_config_name == command.target_config_name &&
            source_upper_position == command.source_upper_position &&
            page_size == command.page_size &&
            source_after_position == command.source_after_position &&
            source_command_ids == command.source_command_ids
        end

        def apply(event)
          if event.is_a?(Events::HistoryMigrationSourceSelectionFrozenV1)
            unless step == EVENT_CLASSES.length - 1 && source_after_position.nil? && migration_id == event.migration_id
              raise InvalidHistoryMigrationHistory, "Source selection must be frozen once before migration start"
            end
            return self.class.new(attributes.merge(
              source_after_position: event.source_after_position,
              source_command_ids: event.source_command_ids
            ))
          end
          expected = EVENT_CLASSES[step]
          unless expected && event.is_a?(expected)
            raise InvalidHistoryMigrationHistory,
                  "Expected #{expected&.name || 'no further event'}, got #{event.class.name}"
          end
          if migration_id && migration_id != event.migration_id
            raise InvalidHistoryMigrationHistory, "HistoryMigration facts disagree on migration_id"
          end

          changes = { step: step + 1, migration_id: event.migration_id }
          case event
          when Events::HistoryMigrationSourceStoreSelectedV1
            changes[:source_config_name] = event.source_config_name
          when Events::HistoryMigrationTargetStoreSelectedV1
            changes[:target_config_name] = event.target_config_name
          when Events::HistoryMigrationSourceRangeFrozenV1
            changes[:source_upper_position] = event.source_upper_position
          when Events::HistoryMigrationPageSizeSelectedV1
            changes[:page_size] = event.page_size
          end

          self.class.new(attributes.merge(changes))
        end
      end
    end
  end
end
