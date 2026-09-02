# frozen_string_literal: true

module ProcessStepExamples
  module_function

  def event(event_store:, source_event:, process_name:, step_name:, subject_kind:, subject_id:)
    marker = Coordinator::Shared::Markers::CodecV2.new.call(
      purpose: "process-step",
      components: [
        { dimension: "process-name", value: process_name },
        { dimension: "source-event-id", value: source_event.id },
        { dimension: "step-name", value: step_name },
        { dimension: "subject-kind", value: subject_kind },
        { dimension: "subject-id", value: subject_id }
      ]
    ).value!.marker
    event_store.read_global_marked(
      Coordinator::Write::GlobalMarkedEventReadCriteria.new(
        stream_context: "CoordinatorControl",
        stream_name: "ProcessStep",
        event_types: [ "ProcessStepPlanned" ],
        markers: [ marker ],
        maximum_count: 1,
        direction: :asc
      )
    ).sole
  end
end
