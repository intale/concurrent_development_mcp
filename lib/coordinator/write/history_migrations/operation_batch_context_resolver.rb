# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class OperationBatchContextResolver
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        stream_identity_allocator:,
        command_input_rebinder:,
        command_input_loader: LegacyCommandInputLoader.new,
        request_id_mapper: LegacyOperationBatchRequestIdMapper.new,
        manifest_builder: OperationBatches::ManifestBuilder.new,
        canonical_json: CanonicalJson.new,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @command_input_rebinder = command_input_rebinder
        @command_input_loader = command_input_loader
        @request_id_mapper = request_id_mapper
        @manifest_builder = manifest_builder
        @canonical_json = canonical_json
        @schema_registry = schema_registry
      end

      def from_creation(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_creation:
      )
        resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_creation_event: source_event,
          source_creation:
        )
      end

      def from_stream(migration_id:, source_config_name:, source_upper_position:, source_event:)
        creation_event = @event_store.read_at(stream_for(source_event), 0)
        unless creation_event && within_frozen_range?(creation_event, source_upper_position)
          return Failure(inconsistent(source_event, "OperationBatch creation is absent from the frozen source range"))
        end

        source_creation = load(creation_event)
        unless source_creation.is_a?(LegacyEvents::OperationBatchCreatedV1)
          return Failure(inconsistent(source_event, "OperationBatch stream does not begin with OperationBatchCreated@1"))
        end

        resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_creation_event: creation_event,
          source_creation:
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def from_identity(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_batch_id:
      )
        creation_event = @event_store.read_at(
          StreamReference.new(
            context: "DevelopmentCoordination",
            stream_name: "OperationBatch",
            stream_id: source_batch_id
          ),
          0
        )
        unless creation_event && within_frozen_range?(creation_event, source_upper_position)
          return Failure(inconsistent(source_event, "OperationBatch creation is absent from the frozen source range"))
        end

        source_creation = load(creation_event)
        unless source_creation.is_a?(LegacyEvents::OperationBatchCreatedV1) &&
            source_creation.batch_id == source_batch_id
          return Failure(inconsistent(source_event, "OperationBatch identity does not resolve to OperationBatchCreated@1"))
        end

        resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_creation_event: creation_event,
          source_creation:,
          membership_event: creation_event
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def resolve(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_creation_event:,
        source_creation:,
        membership_event: source_event
      )
        history = source_history(
          source_event:,
          source_upper_position:,
          source_creation_event:,
          source_creation:,
          membership_event:
        )
        return history if history.failure?

        batch = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event: source_creation_event,
          target_stream_context: "DevelopmentCoordination",
          target_stream_name: "OperationBatch",
          identity_role: "operation-batch"
        )
        return batch if batch.failure?

        target_stream = batch.value!.target_stream
        items = resolve_items(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_creation_event:,
          source_creation:,
          target_batch_id: target_stream.stream_id,
          entries: history.value!
        )
        return items if items.failure?

        Success(
          OperationBatchMigrationContextV1.new(
            source_creation:,
            source_creation_event:,
            target_stream:,
            batch_id: target_stream.stream_id,
            items: items.value!
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def source_history(
        source_event:,
        source_upper_position:,
        source_creation_event:,
        source_creation:,
        membership_event:
      )
        events = @event_store.read(stream_for(source_creation_event), EventQueries::OPERATION_BATCH_HISTORY)
          .select { within_frozen_range?(_1, source_upper_position) }
        unless events.any? { same_event?(_1, membership_event) }
          return Failure(inconsistent(source_event, "source event is absent from its frozen OperationBatch history"))
        end
        unless events.map(&:stream_revision) == (0...events.length).to_a
          return Failure(inconsistent(source_event, "OperationBatch history is not contiguous from revision zero"))
        end

        entries = events.map { [ _1, load(_1) ].freeze }.freeze
        validation = validate_history(
          source_event:,
          source_creation_event:,
          source_creation:,
          entries:
        )
        validation.failure? ? validation : Success(entries)
      rescue EventHistoryLimitExceeded, KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def validate_history(source_event:, source_creation_event:, source_creation:, entries:)
        unless valid_creation?(source_creation_event, source_creation, entries:)
          return Failure(inconsistent(source_event, "OperationBatch creation identity or manifest is inconsistent"))
        end

        outcomes = {}
        continuations = []
        cancellation = nil
        terminal = nil
        entries.drop(1).each_with_index do |(event, payload), offset|
          if terminal
            return Failure(inconsistent(source_event, "OperationBatch contains facts after its terminal event"))
          end
          unless valid_common_event?(event, payload, source_creation:)
            return Failure(inconsistent(source_event, "OperationBatch event identity, schema, or marker is inconsistent"))
          end

          validation = case payload
          when LegacyEvents::OperationBatchItemSucceededV1,
               LegacyEvents::OperationBatchItemRejectedV1
            validate_outcome(
              source_event:,
              source_creation:,
              event:,
              payload:,
              outcomes:
            )
          when LegacyEvents::OperationBatchContinuationRequestedV1
            continuations << [ event, payload ].freeze
            validate_continuation(
              source_event:,
              source_creation:,
              payload:,
              prior_entries: entries.take(offset + 1),
              outcomes:
            )
          when LegacyEvents::OperationBatchCancellationRequestedV1
            if cancellation
              Failure(inconsistent(source_event, "OperationBatch repeats its cancellation request"))
            else
              cancellation = [ event, payload ].freeze
              validate_cancellation_request(source_event:, event:, payload:)
            end
          when LegacyEvents::OperationBatchCompletedV1,
               LegacyEvents::OperationBatchCancelledV1
            terminal = [ event, payload ].freeze
            validate_terminal(
              source_event:,
              source_creation:,
              payload:,
              outcomes:,
              cancellation:
            )
          else
            Failure(inconsistent(source_event, "unsupported fact in OperationBatch source stream"))
          end
          return validation if validation.failure?
        end

        validate_page_progression(source_event:, source_creation:, continuations:, outcomes:)
      end

      def valid_creation?(event, source, entries:)
        actor = Commands::Actor.new(kind: source.requester.kind, id: source.requester.id)
        source.items.map(&:index) == (0...source.total).to_a &&
          source.total == source.items.length &&
          source.items.all? { valid_source_item?(_1, source.target_tool) } &&
          source.manifest_digest == legacy_manifest_digest(source.items) &&
          source.encoded_byte_size == legacy_encoded_byte_size(
            command_id: event.metadata.fetch("command_id"),
            actor:,
            batch_id: source.batch_id,
            target_tool: source.target_tool,
            items: source.items
          ) &&
          event.stream_revision.zero? &&
          event.type == "OperationBatchCreated" &&
          event.metadata.fetch("schema_version") == 1 &&
          event.stream.context == "DevelopmentCoordination" &&
          event.stream.stream_name == "OperationBatch" &&
          event.stream.stream_id == source.batch_id &&
          event.markers.include?("operation-batch:#{source.batch_id}") &&
          event.metadata.fetch("actor_kind") == source.requester.kind &&
          event.metadata.fetch("actor_id") == source.requester.id &&
          entries.first == [ event, source ]
      end

      def legacy_manifest_digest(items)
        @canonical_json.sha256(items.map(&:to_h))
      end

      def legacy_encoded_byte_size(command_id:, actor:, batch_id:, target_tool:, items:)
        @canonical_json.encode(
          command_id:,
          actor: actor.to_h,
          batch_id:,
          target_tool:,
          items: items.map(&:to_h)
        ).bytesize
      end

      def valid_source_item?(item, target_tool)
        document = command_document(item)
        document.tool_name == target_tool &&
          item.canonical_input_digest == @canonical_json.sha256(document.to_h)
      end

      def valid_common_event?(event, payload, source_creation:)
        event.metadata.fetch("schema_version") == 1 &&
          event.stream.context == "DevelopmentCoordination" &&
          event.stream.stream_name == "OperationBatch" &&
          event.stream.stream_id == source_creation.batch_id &&
          event.markers.include?("operation-batch:#{source_creation.batch_id}") &&
          payload.batch_id == source_creation.batch_id
      end

      def validate_outcome(source_event:, source_creation:, event:, payload:, outcomes:)
        item = source_creation.items.find { _1.index == payload.index }
        document = item && command_document(item)
        unless item && !outcomes.key?(payload.index) &&
            payload.command_id == document.command_id &&
            payload.canonical_input_digest == item.canonical_input_digest &&
            event.markers.include?("batch-item:#{source_creation.batch_id}:#{payload.index}")
          return Failure(inconsistent(source_event, "OperationBatch item outcome disagrees with its manifest"))
        end

        validation = if payload.is_a?(LegacyEvents::OperationBatchItemSucceededV1)
                       validate_success(source_event:, item:, payload:)
        else
                       validate_rejection(source_event:, payload:)
        end
        return validation if validation.failure?

        outcomes[payload.index] = [ event, payload ].freeze
        Success()
      end

      def validate_success(source_event:, item:, payload:)
        completion_event = locate(payload.target_completion)
        unless completion_event && exact_reference?(completion_event, payload.target_completion)
          return Failure(inconsistent(source_event, "successful item target completion reference is not exact"))
        end

        completion = load(completion_event)
        document = command_document(item)
        result = payload.result
        valid = completion.is_a?(LegacyEvents::CommandCompletedV1) &&
                completion.command_id == document.command_id &&
                completion.tool_name == document.tool_name &&
                completion.canonical_input_digest == item.canonical_input_digest &&
                completion.status == "ok" &&
                result.status == "ok" &&
                result.command_id == completion.command_id &&
                result.receipt == completion.receipt &&
                result.context_token.nil? &&
                result.summary == completion.summary &&
                result.data == completion.data &&
                result.warnings == completion.warnings &&
                result.next_actions.map(&:to_h) == completion.next_actions.map(&:to_h)
        return Success() if valid

        Failure(inconsistent(source_event, "successful item result disagrees with its Command completion"))
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def validate_rejection(source_event:, payload:)
        result = payload.result
        error = result.data
        message = if error.respond_to?(:message)
          error.message
        else
          error["message"] || error[:message]
        end
        code = error.respond_to?(:code) ? error.code : error["code"] || error[:code]
        details = error.respond_to?(:details) ? error.details : error["details"] || error[:details]
        valid = result.status != "ok" &&
                result.command_id == payload.command_id &&
                result.receipt.nil? &&
                result.context_token.nil? &&
                Types::Identifier.valid?(code) &&
                message.is_a?(String) &&
                details.is_a?(Hash) &&
                result.summary == message
        return Success() if valid

        Failure(inconsistent(source_event, "rejected item result is not a typed domain rejection"))
      end

      def validate_continuation(source_event:, source_creation:, payload:, prior_entries:, outcomes:)
        referenced = prior_entries.find { |event, _body| exact_reference?(event, payload.source_event) }
        valid_source = referenced && (
          referenced.last.is_a?(LegacyEvents::OperationBatchCreatedV1) ||
          referenced.last.is_a?(LegacyEvents::OperationBatchContinuationRequestedV1)
        )
        valid = valid_source &&
                payload.page_start <= payload.page_end &&
                payload.page_end < source_creation.total &&
                payload.page_end - payload.page_start + 1 <= source_creation.page_size &&
                (0...payload.page_start).all? { outcomes.key?(_1) }
        return Success() if valid

        Failure(inconsistent(source_event, "OperationBatch continuation range or source reference is invalid"))
      end

      def validate_cancellation_request(source_event:, event:, payload:)
        valid = event.metadata.fetch("actor_kind") == payload.requester.kind &&
                event.metadata.fetch("actor_id") == payload.requester.id
        return Success() if valid

        Failure(inconsistent(source_event, "OperationBatch cancellation requester attribution is inconsistent"))
      end

      def validate_terminal(source_event:, source_creation:, payload:, outcomes:, cancellation:)
        succeeded = outcomes.values.count { _1.last.is_a?(LegacyEvents::OperationBatchItemSucceededV1) }
        rejected = outcomes.values.count { _1.last.is_a?(LegacyEvents::OperationBatchItemRejectedV1) }
        valid = if payload.is_a?(LegacyEvents::OperationBatchCompletedV1)
                  !cancellation &&
                    outcomes.length == source_creation.total &&
                    payload.succeeded == succeeded &&
                    payload.rejected == rejected &&
                    payload.outcome_manifest_digest == outcome_digest(outcomes)
        else
                  cancellation &&
                    exact_reference?(cancellation.first, payload.cancellation_event) &&
                    payload.succeeded == succeeded &&
                    payload.rejected == rejected &&
                    payload.not_run == source_creation.total - outcomes.length
        end
        return Success() if valid

        Failure(inconsistent(source_event, "OperationBatch terminal counters, digest, or cancellation binding is invalid"))
      end

      def validate_page_progression(source_event:, source_creation:, continuations:, outcomes:)
        expected = source_creation.page_size
        continuations.each do |_event, payload|
          unless payload.page_start == expected && payload.page_end == [
            expected + source_creation.page_size - 1,
            source_creation.total - 1
          ].min
            return Failure(inconsistent(source_event, "OperationBatch continuation pages are not contiguous"))
          end
          expected = payload.page_end + 1
        end
        unless outcomes.keys.all? { _1 < [ expected, source_creation.total ].min }
          return Failure(inconsistent(source_event, "OperationBatch outcome was recorded before its page was requested"))
        end

        Success()
      end

      def outcome_digest(outcomes)
        document = outcomes.sort_by { _1 }.map do |index, (_event, outcome)|
          {
            index:,
            command_id: outcome.command_id,
            canonical_input_digest: outcome.canonical_input_digest,
            status: outcome.is_a?(LegacyEvents::OperationBatchItemSucceededV1) ? "succeeded" : "rejected"
          }
        end
        @canonical_json.sha256(document)
      end

      def resolve_items(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_creation_event:,
        source_creation:,
        target_batch_id:,
        entries:
      )
        outcomes = entries.filter_map do |event, payload|
          [ payload.index, [ event, payload ] ] if payload.respond_to?(:index)
        end.to_h
        items = []
        source_creation.items.each do |source_item|
          outcome = outcomes[source_item.index]&.last
          completion_event = source_completion(outcome)
          allocation_source = completion_event || source_creation_event
          identity_role = completion_event ? "command" : format("operation-batch-item-command-%04d", source_item.index)
          allocation_markers = [
            "operation-batch:#{target_batch_id}",
            "batch-item:#{target_batch_id}:#{source_item.index}"
          ]
          allocation = @stream_identity_allocator.call(
            migration_id:,
            source_config_name:,
            source_event: allocation_source,
            target_stream_context: "CoordinatorControl",
            target_stream_name: "Command",
            identity_role:,
            allocation_markers:
          )
          return allocation if allocation.failure?

          target_stream = allocation.value!.target_stream
          migrated = @command_input_rebinder.call(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            document: source_item.command_input,
            command_id: target_stream.stream_id
          )
          return migrated if migrated.failure?
          migrated = migrated.value!
          source_document = command_document(source_item)
          request_id = @request_id_mapper.call(
            command_id: source_document.command_id,
            source_position: allocation_source.global_position,
            item_index: source_item.index,
            command_history_present: !completion_event.nil?
          )
          target_item = OperationBatches::ItemV2.new(
            index: source_item.index,
            request_id:,
            command_input: migrated.document,
            canonical_input_digest: migrated.canonical_input_digest
          )
          items << OperationBatchItemMigrationV1.new(
            source_item:,
            target_item:,
            target_command_stream: target_stream,
            source_completion_event: completion_event,
            encoded_byte_size: @manifest_builder.item_encoded_byte_size(target_item.submitted_input)
          )
        end
        Success(items.freeze)
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def source_completion(outcome)
        return unless outcome.is_a?(LegacyEvents::OperationBatchItemSucceededV1)

        locate(outcome.target_completion)
      end

      def command_document(item)
        @command_input_loader.call(item.command_input)
      end

      def locate(reference)
        @event_store.read_at(stream_for(reference), reference.stream_revision)
      end

      def exact_reference?(event, reference)
        event.id == reference.event_id &&
          event.type == reference.type &&
          event.stream.context == reference.stream_context &&
          event.stream.stream_name == reference.stream_name &&
          event.stream.stream_id == reference.stream_id &&
          event.stream_revision == reference.stream_revision
      end

      def same_event?(left, right)
        left.id == right.id &&
          left.stream.context == right.stream.context &&
          left.stream.stream_name == right.stream.stream_name &&
          left.stream.stream_id == right.stream.stream_id &&
          left.stream_revision == right.stream_revision
      end

      def within_frozen_range?(event, source_upper_position)
        source_upper_position.nil? || event.global_position <= source_upper_position
      end

      def stream_for(value)
        stream = value.respond_to?(:stream) ? value.stream : value
        StreamReference.new(
          context: stream.respond_to?(:context) ? stream.context : value.stream_context,
          stream_name: stream.respond_to?(:stream_name) ? stream.stream_name : value.stream_name,
          stream_id: stream.respond_to?(:stream_id) ? stream.stream_id : value.stream_id
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "OperationBatch source is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
