# frozen_string_literal: true

module Coordinator::Write::ProcessSteps
  class Planner
    include Dry::Monads[:result]

    MARKER_PURPOSE = "process-step"

    def initialize(
      event_store:,
      natural_key_registry: Coordinator::Write::NaturalKeys::Registry.new(event_store:),
      marker_codec: Coordinator::Shared::Markers::CodecV2.new,
      id_generator: Coordinator::Shared::IdGenerator.new,
      stream_factory: Coordinator::Write::StreamFactory.new,
      event_factory: Coordinator::Write::EventFactory.new,
      event_schema_registry: Coordinator::Write::EventSchemaRegistry.new
    )
      @natural_key_registry = natural_key_registry
      @marker_codec = marker_codec
      @id_generator = id_generator
      @stream_factory = stream_factory
      @event_factory = event_factory
      @event_schema_registry = event_schema_registry
    end

    def call(source_event:, process_name:, step_name:, subject_kind:, subject_id:, rule_version:, allocate_target_entity:)
      command = prepare_command(
        source_event:,
        process_name:,
        step_name:,
        subject_kind:,
        subject_id:,
        rule_version:,
        allocate_target_entity:
      )
      encoded = @marker_codec.call(purpose: MARKER_PURPOSE, components: marker_components(command))
      return Failure(encoded.failure) if encoded.failure?

      marker = encoded.value!.marker
      @natural_key_registry.call(
        selector: selector(marker),
        proposed_stream: @stream_factory.process_step(command.process_step_id),
        build_event: -> { build_event(command, marker:, source_event:) },
        identity_from: ->(event) { identity_from(event, command) }
      )
    end

    private

    def prepare_command(
      source_event:,
      process_name:,
      step_name:,
      subject_kind:,
      subject_id:,
      rule_version:,
      allocate_target_entity:
    )
      FindOrPlanProcessStepV1.new(
        command_id: @id_generator.uuid_v7,
        event_id: @id_generator.uuid_v7,
        process_step_id: @id_generator.uuid_v7,
        process_name:,
        step_name:,
        source_event_id: source_event.id,
        subject_kind:,
        subject_id:,
        target_command_id: @id_generator.uuid_v7,
        target_entity_id: allocate_target_entity ? @id_generator.uuid_v7 : nil,
        rule_version:
      )
    end

    def marker_components(command)
      [
        { dimension: "process-name", value: command.process_name },
        { dimension: "source-event-id", value: command.source_event_id },
        { dimension: "step-name", value: command.step_name },
        { dimension: "subject-kind", value: command.subject_kind },
        { dimension: "subject-id", value: command.subject_id }
      ]
    end

    def selector(marker)
      Coordinator::Write::NaturalKeys::Registry::SelectorV1.new(
        stream_context: "CoordinatorControl",
        stream_name: "ProcessStep",
        event_type: "ProcessStepPlanned",
        marker:
      )
    end

    def build_event(command, marker:, source_event:)
      event = Coordinator::Write::Events::ProcessStepPlannedV1.new(
        process_step_id: command.process_step_id,
        process_name: command.process_name,
        step_name: command.step_name,
        source_event_id: command.source_event_id,
        subject_kind: command.subject_kind,
        subject_id: command.subject_id,
        target_command_id: command.target_command_id,
        target_entity_id: command.target_entity_id
      )
      metadata = MetadataV1.new(
        command_id: command.command_id,
        actor_kind: "system",
        actor_id: command.process_name,
        actor_authenticated: false,
        recorded_by: "coordinator",
        rule_version: command.rule_version
      )

      @event_factory.build!(
        event:,
        event_id: command.event_id,
        metadata:,
        markers: [ marker ],
        caused_by: source_event
      )
    end

    def identity_from(event, command)
      payload = @event_schema_registry.load(
        type: event.type,
        schema_version: event.metadata.fetch("schema_version"),
        data: event.data
      )
      return unless natural_tuple(payload) == natural_tuple(command)

      payload.process_step_id
    rescue KeyError, ArgumentError
      nil
    end

    def natural_tuple(value)
      [ value.process_name, value.source_event_id, value.step_name, value.subject_kind, value.subject_id ]
    end
  end
end
