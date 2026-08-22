# frozen_string_literal: true

module Coordinator::Write
  class ReadinessInvocation < Value
    attribute :command, Types.Instance(Commands::EvaluateWorkItemReadiness)
    attribute :source_event, Types.Instance(PgEventstore::Event)
    attribute :source_reference, Types.Instance(EventReference)
    attribute :source_change_set_id, Types::Identifier
  end
end
