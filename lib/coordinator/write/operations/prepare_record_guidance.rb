# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareRecordGuidance < Dry::Operation
      def initialize(contract: Contracts::RecordGuidance.new)
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
            message: "RecordGuidance input is invalid",
            details: result.errors.to_h
          )
        )
      end

      def build_command(attributes)
        actor = attributes.fetch(:actor)
        anchors = attributes.fetch(:anchors)

        Success(
          Commands::RecordGuidance.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
            message_id: attributes.fetch(:message_id),
            conversation_id: attributes.fetch(:conversation_id),
            source: attributes.fetch(:source),
            text: attributes.fetch(:text),
            anchors: GuidanceAnchorsV1.new(
              repository_ids: anchors.fetch(:repository_ids).sort,
              change_set_id: anchors.fetch(:change_set_id),
              work_item_id: anchors.fetch(:work_item_id),
              attempt_id: anchors.fetch(:attempt_id)
            )
          )
        )
      end
    end
  end
end
