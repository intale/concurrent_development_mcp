# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class IntegrationFactV1 < Value
      attribute :payload, Events::RepositoryIntegrationRecordedV1
      attribute :event, EventReference
    end
  end
end
