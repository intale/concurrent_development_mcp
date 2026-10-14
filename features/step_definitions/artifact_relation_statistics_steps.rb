# frozen_string_literal: true

Then("the relationship statistics Saga records one successful source observation") do
  start_process_subscriptions
  relation_id = @relation_replay_results.first.dig("data", "relation_id")
  source = artifact_relation_events(relation_id).find { _1.type == "DevelopmentArtifactRelationDeclared" }
  loader = Coordinator::Write::ProjectionStatistics::ArtifactRelationsLoader.new(event_store:)
  registry = Coordinator::Write::NaturalKeys::Registry.new(event_store:)
  statistics_id = nil
  eventually("registered relationship-statistics Saga to settle") do
    found = registry.find(selector: loader.selector(@replay_parent),
      identity_from: ->(event) { event.data.fetch("statistics_id") })
    statistics_id = found.value!&.identity if found.success?
    settled = statistics_id && loader.reconciled?(statistics_id, source.id)
    [ settled, { statistics_id:, settled: } ]
  end

  events = event_store.read(streams.development_artifact_relation_statistics(statistics_id),
    Coordinator::Write::EventReadCriteria.new(
      event_types: Coordinator::Write::EventQueries::DEVELOPMENT_ARTIFACT_RELATION_STATISTICS_CONTROL.event_types,
      maximum_count: 8, direction: :asc))
  assert_acceptance_equal(
    %w[DevelopmentArtifactRelationStatisticsAssigned DevelopmentArtifactRelationsNumberChanged
       DevelopmentArtifactRelationsNumberChanged DevelopmentArtifactRelationsReconciled],
    events.map(&:type), "Idempotent relationship-statistics chronology")
  assert_acceptance_equal(
    [ [ 0, 0 ], [ 1, 1 ] ],
    events.select { _1.type == "DevelopmentArtifactRelationsNumberChanged" }
      .map { [ _1.data.fetch("active_relations_number"), _1.data.fetch("lifetime_relations_number") ] },
    "Authoritative absolute relationship numbers")
  assert_acceptance_equal(source.id, events.last.data.fetch("source_event_id"), "Exact successful Saga source")
  assert_acceptance_equal([ source.correlation_id ], events.map(&:correlation_id).uniq, "Saga native correlation")
  assert_acceptance(events.all?(&:causation_id), "Every statistics fact names its native immediate parent")
end
