# frozen_string_literal: true

module Coordinator
  class ReadinessInvocation < Value
    attribute :command, Types.Instance(Commands::EvaluateWorkItemReadiness)
    attribute :source, Types.Instance(ChangeSetActivationSource)
  end
end
