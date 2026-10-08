# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareStartHistoryMigration < Dry::Operation
      def initialize(
        contract: Contracts::StartHistoryMigration.new,
        store_registry: HistoryMigrations::StoreRegistry.new,
        id_generator: IdGenerator.new
      )
        @contract = contract
        @store_registry = store_registry
        @id_generator = id_generator
      end

      def call(input)
        attributes = step validate(input)
        source_config_name = HistoryMigrations::StoreRegistry::SOURCE_CONFIG_NAME
        target_config_name = HistoryMigrations::StoreRegistry::TARGET_CONFIG_NAME

        step ensure_store_available(source_config_name, role: "source")
        step ensure_store_available(target_config_name, role: "target")

        if attributes.key?(:source_after_position)
          step HistoryMigrations::SourceSelectionValidator.new(
            source_reader: HistoryMigrations::SourceReader.new(client: @store_registry.client(source_config_name))
          ).call(
            after_position: attributes.fetch(:source_after_position),
            upper_position: attributes.fetch(:source_upper_position),
            command_ids: attributes.fetch(:source_command_ids)
          )
        end

        source_head = HistoryMigrations::SourceReader.new(
          client: @store_registry.client(source_config_name)
        ).head_position
        source_upper_position = attributes.fetch(:source_upper_position, source_head)
        if source_upper_position && (!source_head || source_upper_position > source_head)
          step Failure(
            OutcomeError.new(
              code: :invalid_input,
              message: "Frozen source upper position exceeds the current source head",
              details: { source_upper_position:, source_head: }
            )
          )
        end

        step build_command(
          attributes,
          source_config_name:,
          target_config_name:,
          source_upper_position:
        )
      end

      private

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "StartHistoryMigration input is invalid",
            details: result.errors.to_h
          )
        )
      end

      def ensure_store_available(config_name, role:)
        return Success() if @store_registry.available?(config_name)

        Failure(
          OutcomeError.new(
            code: :history_migration_store_unavailable,
            message: "HistoryMigration #{role} store is not configured",
            details: { config_name:, store_role: role }
          )
        )
      end

      def build_command(attributes, source_config_name:, target_config_name:, source_upper_position:)
        actor = attributes.fetch(:actor)
        Success(
          Commands::StartHistoryMigration.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
            migration_id: @id_generator.uuid_v7,
            source_config_name:,
            target_config_name:,
            source_upper_position:,
            page_size: attributes.fetch(:page_size, Types::HISTORY_MIGRATION_PAGE_SIZE_MAXIMUM),
            source_after_position: attributes[:source_after_position],
            source_command_ids: attributes.fetch(:source_command_ids, []).sort
          )
        )
      end
    end
  end
end
