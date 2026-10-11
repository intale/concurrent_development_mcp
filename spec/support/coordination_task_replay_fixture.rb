# frozen_string_literal: true

class CoordinationTaskReplayFixture
  def self.submit(target, event_store:, streams:)
    task_id, command_id, registration_id, submission_id, migration_id = Array.new(5) { SecureRandom.uuid_v7 }
    digest = Coordinator::Write::CommandInputDigest.new
    rebound = target.class.new(target.attributes.merge(command_id:))
    input = digest.document(rebound)
    command = Coordinator::Write::Commands::SubmitCoordinationTask.new(
      task_id:, command_id:, request_id: target.command_id,
      command_input: input, tool_name: input.tool_name,
      canonical_input_digest: digest.request(target), ttl_ms: nil, poll_interval_ms: 500
    )
    facts = Coordinator::Write::Domain::CoordinationTasks::Submit.new.call(
      state: Coordinator::Write::Domain::CoordinationTasks::State.initial, command:
    ).value!
    metadata = Coordinator::Write::Metadata::CanonicalCommandV1.new(
      command_id:, actor_kind: target.actor.kind, actor_id: target.actor.id,
      recorded_by: "coordinator", policy_version: nil, canonical_input_digest: command.canonical_input_digest
    )
    request_marker = Coordinator::Write::CommandLifecycle::RequestMarker.new.call(
      actor: target.actor, request_id: target.command_id
    )
    markers = [ "command:#{command_id}", "task:#{task_id}", request_marker ]
    factory = Coordinator::Write::EventFactory.new
    source = event_store.multiple do
      registration = factory.build!(event: facts.first, event_id: registration_id, metadata:, markers:)
      parent = event_store.append(streams.command(command_id), [ registration ]).sole
      submission = factory.build!(
        event: facts.last, event_id: submission_id, metadata:, caused_by: parent,
        markers: markers + [
          Coordinator::Write::Tasks::ExecutionLane.new.marker(task_id), "tool:#{command.tool_name}",
          "history-migration:#{migration_id}", "migration-target-event:#{submission_id}"
        ]
      )
      submission.metadata["migration_id"] = migration_id
      event_store.append(streams.coordination_task(task_id), [ submission ]).sole
    end
    [ task_id, source ]
  end
end
