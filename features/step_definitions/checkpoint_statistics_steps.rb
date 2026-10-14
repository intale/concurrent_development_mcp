# frozen_string_literal: true

Then("Candidate {string} is counted once by the registered checkpoint statistics Saga") do |candidate_id|
  start_process_subscriptions
  coordination = @candidate_coordination
  loader = Coordinator::Write::ProjectionStatistics::CheckpointsLoader.new(event_store:)
  registry = Coordinator::Write::NaturalKeys::Registry.new(event_store:)
  statistics_id = nil
  eventually("registered checkpoint statistics Saga to settle") do
    found = registry.find(selector: loader.selector(
      change_set_id: coordination.dig(:ids, :change_set_id), repository_id: coordination.fetch(:repository_id)),
      identity_from: ->(event) { event.data.fetch("statistics_id") })
    statistics_id = found.value!&.identity if found.success?
    settled = statistics_id && loader.counted?(statistics_id, candidate_id)
    [ settled, { statistics_id:, settled: } ]
  end

  facts = event_store.read(streams.checkpoint_statistics(statistics_id),
    Coordinator::Write::EventReadCriteria.new(
      event_types: Coordinator::Write::EventQueries::CHECKPOINT_STATISTICS_CONTROL.event_types,
      maximum_count: 8, direction: :asc))
  assert_acceptance_equal(
    %w[ChangeSetRepositoryCheckpointStatisticsAssigned ChangeSetRepositoryCheckpointNumberChanged
       ChangeSetRepositoryCheckpointNumberChanged CandidateCheckpointCounted],
    facts.map(&:type), "Checkpoint statistics chronology")
  assert_acceptance_equal([ 0, 1 ],
    facts.select { _1.type == "ChangeSetRepositoryCheckpointNumberChanged" }.map { _1.data.fetch("checkpoints_number") },
    "Absolute checkpoint count")
  assert_acceptance_equal(candidate_id, facts.last.data.fetch("candidate_id"), "Exact counted Candidate")
  source = event_store.read(streams.candidate(candidate_id), Coordinator::Write::EventReadCriteria.new(
    event_types: [ "CandidateSubmitted" ], maximum_count: 1, direction: :asc)).sole
  assert_acceptance_equal([ source.correlation_id ], facts.map(&:correlation_id).uniq, "Native statistics correlation")
  assert_acceptance(facts.all?(&:causation_id), "Checkpoint facts name their immediate process-step parents")
end
