# frozen_string_literal: true

module HistoryMigrationWaveDispatch
  def self.call(dispatcher:, migration_id:, source_config_name:, source_upper_position:, source_event:)
    results = (0..Coordinator::Shared::Types::HISTORY_MIGRATION_DEPENDENCY_WAVE_MAXIMUM).map do |dependency_wave|
      dispatcher.call(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        dependency_wave:
      )
    end
    failure = results.find(&:failure?)
    return failure if failure

    writes = results.map(&:value!)
    events = writes.flat_map(&:events)
    outcomes = writes.map(&:outcome).reject { _1 == "skipped" }
    Dry::Monads::Result::Success.new(
      Coordinator::Write::HistoryMigrations::TargetWriteResultV1.new(
        events:,
        outcome: combined_outcome(events:, outcomes:)
      )
    )
  end

  def self.combined_outcome(events:, outcomes:)
    return "skipped" if events.empty?
    return "written" if outcomes.uniq == [ "written" ]
    return "existing" if outcomes.uniq == [ "existing" ]

    "mixed"
  end
  private_class_method :combined_outcome
end
