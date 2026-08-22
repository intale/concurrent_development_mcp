# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class DecisionEnforcementV1 < Value
      attribute :level, Types::EnforcementLevel
      attribute :retroactivity, Types::RetroactivityKind
      attribute :on_violation, Types::ViolationAction
    end
  end
end
