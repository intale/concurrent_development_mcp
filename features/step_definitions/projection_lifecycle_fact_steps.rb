# frozen_string_literal: true

Then("the Batch records terminal outcome {string} independently of read models") do |outcome|
  events = operation_batch_events
  fact = events.select { _1.type == "OperationBatchOutcomeRecorded" }.sole
  terminal = events.last
  assert_acceptance_equal({ "batch_id" => @operation_batch_id, "outcome" => outcome }, fact.data, "Cohesive terminal outcome")
  assert_acceptance_equal(fact.stream_revision + 1, terminal.stream_revision, "Outcome and terminal chronology")
  assert_acceptance_equal(fact.metadata.fetch("command_id"), terminal.metadata.fetch("command_id"), "One terminal command")
  assert_acceptance_equal(fact.causation_id, terminal.causation_id, "One immediate parent")
  assert_acceptance_equal(fact.correlation_id, terminal.correlation_id, "Native Batch correlation")
end

Then("the final integration requests composite verification as its own fact") do
  release_set_id = @release_set_arguments.fetch(:release_set_id)
  events = release_set_lifecycle_events(release_set_id)
  request = events.select { _1.type == "ReleaseSetVerificationRequested" }.sole
  link = events.find { _1.stream_revision == request.stream_revision - 1 }
  assert_acceptance_equal({ "release_set_id" => release_set_id }, request.data, "Cohesive verification request")
  assert_acceptance_equal("RepositoryIntegrationMergeLinked", link.type, "Final member integration precedes request")
  assert_acceptance_equal(link.id, request.causation_id, "Actual immediate parent")
  assert_acceptance_equal(link.correlation_id, request.correlation_id, "Native ReleaseSet correlation")
end
