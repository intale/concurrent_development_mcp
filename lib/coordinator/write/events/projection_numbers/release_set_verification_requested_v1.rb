# frozen_string_literal: true

module Coordinator::Write::Events::ProjectionNumbers
  class ReleaseSetVerificationRequestedV1 < Coordinator::Write::Events::Base
    contract type: "ReleaseSetVerificationRequested", version: 1

    attribute :release_set_id, Coordinator::Write::Types::Identifier
  end
end
