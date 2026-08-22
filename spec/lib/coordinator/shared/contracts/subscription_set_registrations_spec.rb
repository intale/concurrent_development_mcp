# frozen_string_literal: true

RSpec.describe Coordinator::Shared::Contracts::SubscriptionSetRegistrations do
  subject(:contract) { described_class.new }

  it "accepts several uniquely named registrations for one set" do
    registrations = [
      registration("coordinator-process-managers-v1", "readiness-v1"),
      registration("coordinator-process-managers-v1", "dependency-v1")
    ]

    result = contract.call(
      set_name: "coordinator-process-managers-v1",
      registrations:
    )

    expect(result).to be_success
  end

  it "rejects mixed sets and duplicate subscription names" do
    mixed = contract.call(
      set_name: "coordinator-process-managers-v1",
      registrations: [ registration("another-set", "readiness-v1") ]
    )
    duplicate = contract.call(
      set_name: "coordinator-process-managers-v1",
      registrations: [
        registration("coordinator-process-managers-v1", "readiness-v1"),
        registration("coordinator-process-managers-v1", "readiness-v1")
      ]
    )

    expect(mixed.errors.to_h).to include(:registrations)
    expect(duplicate.errors.to_h).to include(:registrations)
  end

  it "treats set name and subscription name together as the durable identity" do
    first = registration("coordinator-process-managers-v1", "readiness-v1").definition.identity
    same = registration("coordinator-process-managers-v1", "readiness-v1").definition.identity
    another_set = registration("coordinator-read-models-v1", "readiness-v1").definition.identity

    expect(first).to eq(same)
    expect(first).not_to eq(another_set)
  end

  def registration(set_name, subscription_name)
    Coordinator::Shared::Subscriptions::Registration.new(
      definition: Coordinator::Shared::Subscriptions::Definition.new(
        set_name:,
        subscription_name:,
        stream_context: "DevelopmentPlanning",
        stream_name: "ChangeSet",
        event_type: "ChangeSetActivated"
      ),
      handler: ->(_event) { }
    )
  end
end
