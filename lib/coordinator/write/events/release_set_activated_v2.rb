# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ReleaseSetActivatedV2 < Base
      contract type: "ReleaseSetActivated", version: 2

      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :activation_point, ReleaseSets::ActivationPointV2
    end
  end
end
