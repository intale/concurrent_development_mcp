# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecutePublishSkillRevision < Dry::Operation
      TOOL_NAME = "skill_publish"
      MARKER_CODEC_VERSION = "compound-marker-v2"

      def initialize(
        event_store:,
        preparer: PreparePublishSkillRevision.new,
        decider: Domain::Skills::GranularPublish.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        marker_builder: Skills::MarkerBuilder.new,
        natural_key_registry: NaturalKeys::Registry.new(event_store:),
        completion_builder: CommandResultBuilder.new
      )
        @event_store = event_store
        @preparer = preparer
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @marker_builder = marker_builder
        @natural_key_registry = natural_key_registry
        @completion_builder = completion_builder
      end

      def call(input)
        command = step @preparer.call(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        steps do
          preparation = prepare_logical_values(command)
          step @event_store.multiple { execute_attempt(command:, preparation:, caused_by:) }
        end
      end

      private

      def prepare_logical_values(command)
        SkillPublicationPreparationV2.new(
          recorded_at: @clock.now,
          input_digest: @input_digest.skill_publish(command),
          skill_revision_id: @id_generator.uuid_v7,
          registration_event_id: @id_generator.uuid_v7,
          revision_created_event_id: @id_generator.uuid_v7,
          description_event_id: @id_generator.uuid_v7,
          instructions_event_id: @id_generator.uuid_v7,
          asset_ids: command.assets.map { build_asset_ids },
          publication_event_id: @id_generator.uuid_v7
        )
      end

      def build_asset_ids
        Skills::AssetPublicationIdsV1.new(
          asset_id: @id_generator.uuid_v7,
          created_event_id: @id_generator.uuid_v7,
          path_event_id: @id_generator.uuid_v7,
          content_event_id: @id_generator.uuid_v7,
          executability_event_id: @id_generator.uuid_v7,
          assignment_event_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        resolved = resolve_skill(command)
        return resolved if resolved.failure?

        command = resolved.value!
        state_result = load_skill_state(command.skill_id)
        return state_result if state_result.failure?

        state, prior_publication = state_result.value!
        decision_result = @decider.call(
          state:,
          command:,
          skill_stream: @stream_factory.skill(command.skill_id),
          revision_stream: @stream_factory.skill_revision(preparation.skill_revision_id),
          asset_streams: preparation.asset_ids.map { @stream_factory.skill_asset(_1.asset_id) },
          revision_id: preparation.skill_revision_id
        )
        return decision_result if decision_result.failure?

        decision = decision_result.value!
        ActiveSupport::Notifications.instrument(
          "coordinator.command_boundary",
          operation: TOOL_NAME,
          command_id: command.command_id
        )
        persisted_events = persist_domain_plan(
          decision.event_plan,
          command:,
          preparation:,
          caused_by:
        )
        publication_event = persisted_events.reverse.find { _1.type == "SkillRevisionPublished" } || prior_publication
        raise "Skill publication decision has no authoritative publication event" unless publication_event

        Success(
          @completion_builder.skill_publish(
            command:,
            revision: decision.revision,
            outcome: decision.outcome,
            publication_event:,
            input_digest: preparation.input_digest,
            persisted_events:,
            completed_at: preparation.recorded_at
          )
        )
      end

      def resolve_skill(command)
        result = @natural_key_registry.find(
          selector: NaturalKeys::Registry::SelectorV1.new(
            stream_context: "AgentKnowledge",
            stream_name: "Skill",
            event_type: "SkillRegistered",
            marker: @marker_builder.natural_key(name: command.name, scope: command.scope)
          ),
          identity_from: ->(event) { skill_identity_from(event, command) }
        )
        return registry_failure(result.failure) if result.failure?
        return Success(command) unless result.value!

        Success(with_skill_id(command, result.value!.identity))
      end

      def skill_identity_from(event, command)
        registration = load_event(event)
        return unless registration.is_a?(Events::SkillRegisteredV1)
        return unless registration.name == command.name && registration.scope == command.scope

        registration.skill_id
      rescue EventSchemaRegistry::UnknownSchema, EventSchemaRegistry::SchemaMismatch,
             Dry::Struct::Error, KeyError, ArgumentError
        nil
      end

      def with_skill_id(command, skill_id)
        Commands::PublishSkillRevision.new(
          command_id: command.command_id,
          actor: command.actor,
          skill_id:,
          name: command.name,
          scope: command.scope,
          expected_revision: command.expected_revision,
          description: command.description,
          instructions: command.instructions,
          assets: command.assets,
          content_digest: command.content_digest
        )
      end

      def registry_failure(error)
        Failure(
          OutcomeError.new(
            code: :skill_identity_registry_invalid,
            message: error.message,
            details: error.to_h
          )
        )
      end

      def load_skill_state(skill_id)
        events = @event_store.read_grouped(
          @stream_factory.skill(skill_id),
          GroupedEventReadCriteria.new(
            event_types: [ "SkillRegistered", "SkillRevisionPublished" ],
            direction: :desc
          )
        )
        return Success([ Skills::SkillStateV1.initial(skill_id:), nil ]) if events.empty?

        registration_event = events.find { _1.type == "SkillRegistered" }
        publication_event = events.find { _1.type == "SkillRevisionPublished" }
        registration = registration_event && load_event(registration_event)
        publication = publication_event && load_event(publication_event)

        case publication
        when Events::SkillRevisionPublishedV3
          unless registration.is_a?(Events::SkillRegisteredV1)
            return Failure(
              OutcomeError.new(
                code: :stored_skill_revision_invalid,
                message: "Persisted granular Skill state is missing its registration fact",
                details: { skill_id: }
              )
            )

          end

          Success([
            Skills::SkillStateV1.new(
              skill_id: registration.skill_id,
              name: registration.name,
              scope: registration.scope,
              skill_revision_id: publication.skill_revision_id,
              revision: publication.revision,
              content_digest: publication_event.metadata.fetch("content_digest")
            ),
            publication_event
          ])
        when Events::SkillRevisionPublishedV2
          Success([
            Skills::SkillStateV1.new(
              skill_id: publication.skill_id,
              name: publication.name,
              scope: publication.scope,
              skill_revision_id: nil,
              revision: publication.revision,
              content_digest: publication.content_digest
            ),
            publication_event
          ])
        else
          Failure(
            OutcomeError.new(
              code: :stored_skill_revision_invalid,
              message: "Persisted Skill state is missing its registration fact",
              details: { skill_id: }
            )
          )
        end
      rescue EventSchemaRegistry::UnknownSchema, EventSchemaRegistry::SchemaMismatch,
             Dry::Struct::Error, KeyError, ArgumentError => error
        Failure(
          OutcomeError.new(
            code: :stored_skill_revision_invalid,
            message: "Persisted Skill state is invalid",
            details: { skill_id:, errors: { payload: [ error.message ] } }
          )
        )
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def persist_domain_plan(plan, command:, preparation:, caused_by:)
        return [] unless plan

        built = plan.writes.map do |write|
          [
            write.stream,
            @event_factory.build!(
              event: write.event,
              event_id: domain_event_id(write.event, preparation),
              metadata: event_metadata(write.event, command, preparation),
              markers: event_markers(write.event, command),
              caused_by:
            )
          ]
        end

        persisted = []
        built.chunk_while { |left, right| left.first == right.first }.each do |group|
          persisted.concat(@event_store.append(group.first.first, group.map(&:last)))
        end
        persisted
      end

      def domain_event_id(event, preparation)
        case event
        when Events::SkillRegisteredV1 then preparation.registration_event_id
        when Events::SkillRevisionCreatedV1 then preparation.revision_created_event_id
        when Events::SkillRevisionDescriptionDefinedV1 then preparation.description_event_id
        when Events::SkillRevisionInstructionsDefinedV1 then preparation.instructions_event_id
        when Events::SkillRevisionPublishedV3 then preparation.publication_event_id
        else
          asset_ids = preparation.asset_ids.find { _1.asset_id == event.asset_id }
          raise "Missing prepared Skill asset identity for #{event.class.name}" unless asset_ids

          case event
          when Events::SkillAssetCreatedV1 then asset_ids.created_event_id
          when Events::SkillAssetPathDefinedV1 then asset_ids.path_event_id
          when Events::SkillAssetContentDefinedV1 then asset_ids.content_event_id
          when Events::SkillAssetExecutabilityDefinedV1 then asset_ids.executability_event_id
          when Events::SkillAssetAddedToRevisionV1 then asset_ids.assignment_event_id
          else raise "Unexpected Skill publication event #{event.class.name}"
          end
        end
      end

      def event_metadata(event, command, preparation)
        attributes = metadata_attributes(command)
        case event
        when Events::SkillRegisteredV1
          Metadata::MarkerCodecV1.new(**attributes, marker_codec_version: MARKER_CODEC_VERSION)
        when Events::SkillRevisionInstructionsDefinedV1
          content_metadata(attributes, encoding: "utf-8", media_type: "text/markdown", content: event.instructions)
        when Events::SkillAssetContentDefinedV1
          asset_index = preparation.asset_ids.index { _1.asset_id == event.asset_id }
          asset = asset_index && command.assets.fetch(asset_index)
          raise "Missing Skill asset content metadata" unless asset

          content_metadata(
            attributes,
            encoding: asset.content.encoding,
            media_type: asset.content.media_type,
            content: event.content,
            content_sha256: asset.content.content_sha256,
            byte_size: asset.content.byte_size
          )
        when Events::SkillRevisionPublishedV3
          Metadata::SkillPublicationV3.new(**attributes, content_digest: command.content_digest)
        else
          EventMetadata.new(**attributes)
        end
      end

      def content_metadata(attributes, encoding:, media_type:, content:, content_sha256: nil, byte_size: nil)
        bytes = encoding == "binary" ? content.unpack1("m0") : content.b
        Metadata::ContentV1.new(
          **attributes,
          encoding:,
          media_type:,
          byte_size: byte_size || bytes.bytesize,
          content_sha256: content_sha256 || "sha256:#{OpenSSL::Digest::SHA256.hexdigest(bytes)}"
        )
      end

      def metadata_attributes(command)
        {
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "skill-repository/v2"
        }
      end

      def event_markers(event, command)
        markers = [ "skill:#{command.skill_id}", "command:#{command.command_id}" ]
        case event
        when Events::SkillRegisteredV1
          markers << @marker_builder.natural_key(name: command.name, scope: command.scope)
        when Events::SkillRevisionCreatedV1,
             Events::SkillRevisionDescriptionDefinedV1,
             Events::SkillRevisionInstructionsDefinedV1,
             Events::SkillAssetAddedToRevisionV1
          markers << "skill-revision:#{event.skill_revision_id}"
        when Events::SkillAssetCreatedV1,
             Events::SkillAssetPathDefinedV1,
             Events::SkillAssetContentDefinedV1,
             Events::SkillAssetExecutabilityDefinedV1
          markers << "skill-asset:#{event.asset_id}"
        when Events::SkillRevisionPublishedV3
          markers << "skill-revision:#{event.skill_revision_id}"
        end
        markers.uniq.freeze
      end
    end
  end
end
