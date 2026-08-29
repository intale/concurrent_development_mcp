# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareRenewLeaseSet < Dry::Operation
      def initialize(contract: Contracts::RenewLeaseSet.new)
        @contract = contract
      end

      def call(input)
        attributes = step validate(input)
        step build_command(attributes)
      end

      private

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "RenewLeaseSet input is invalid",
            details: result.errors.to_h
          )
        )
      end

      def build_command(attributes)
        actor = attributes.fetch(:actor)
        leases = attributes.fetch(:leases).map do |reference|
          LeaseRenewalReferenceV2.new(reference)
        end.sort_by { _1.resource_id.b }

        Success(
          Commands::RenewLeaseSet.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
            change_set_id: attributes.fetch(:change_set_id),
            work_item_id: attributes.fetch(:work_item_id),
            attempt_id: attributes.fetch(:attempt_id),
            lease_set_id: attributes.fetch(:lease_set_id),
            leases:,
            lease_duration_seconds: attributes.fetch(:lease_duration_seconds)
          )
        )
      end
    end
  end
end
