# frozen_string_literal: true

module Coordinator::Write::NaturalKeys
  class Registry
    include Dry::Monads[:result]

    class SelectorV1 < Coordinator::Write::Value
      attribute :stream_context, Coordinator::Write::Types::Identifier
      attribute :stream_name, Coordinator::Write::Types::Identifier
      attribute :event_type, Coordinator::Write::Types::Identifier
      attribute :marker, Coordinator::Write::Types::ResourceMarker
    end

    class ResolutionV1 < Coordinator::Write::Value
      attribute :identity, Coordinator::Write::Types::UuidV7
      attribute :event, Coordinator::Write::Types.Instance(PgEventstore::Event)
      attribute :outcome, Coordinator::Write::Types::String.enum("created", "existing")
    end

    class IntegrityErrorV1 < Coordinator::Write::Value
      attribute :code,
                Coordinator::Write::Types::Symbol.enum(
                  :duplicate_registration,
                  :existing_registration_invalid,
                  :proposed_stream_occupied,
                  :proposal_invalid
                )
      attribute :message, Coordinator::Write::Types::String
      attribute :marker, Coordinator::Write::Types::ResourceMarker
      attribute :event_ids,
                Coordinator::Write::Types::Array.of(Coordinator::Write::Types::String).constrained(max_size: 3)
      attribute :proposed_stream_id, Coordinator::Write::Types::UuidV7.optional
    end

    def initialize(event_store:)
      @event_store = event_store
    end

    def call(selector:, proposed_stream:, build_event:, identity_from:)
      @event_store.multiple do
        resolve(
          selector:,
          proposed_stream:,
          build_event:,
          identity_from:
        )
      end
    rescue Coordinator::Write::EventHistoryLimitExceeded
      Failure(integrity_error(:duplicate_registration, selector:, event_ids: [], proposed_stream:))
    end

    private

    def resolve(selector:, proposed_stream:, build_event:, identity_from:)
      events = @event_store.read_global_marked(criteria(selector))
      if events.length > 1
        return Failure(
          integrity_error(
            :duplicate_registration,
            selector:,
            event_ids: events.map(&:id),
            proposed_stream:
          )
        )
      end

      return resolve_existing(events.sole, selector:, proposed_stream:, identity_from:) if events.any?

      resolve_new(selector:, proposed_stream:, build_event:, identity_from:)
    end

    def resolve_existing(event, selector:, proposed_stream:, identity_from:)
      identity = normalized_identity(identity_from.call(event))
      unless identity && persisted_registration_matches?(event, selector:, identity:)
        return Failure(
          integrity_error(
            :existing_registration_invalid,
            selector:,
            event_ids: [ event.id ],
            proposed_stream:
          )
        )
      end

      Success(ResolutionV1.new(identity:, event:, outcome: "existing"))
    end

    def resolve_new(selector:, proposed_stream:, build_event:, identity_from:)
      occupied = @event_store.read_at(proposed_stream, 0)
      if occupied
        return Failure(
          integrity_error(
            :proposed_stream_occupied,
            selector:,
            event_ids: [ occupied.id ],
            proposed_stream:
          )
        )
      end

      event = build_event.call
      identity = normalized_identity(identity_from.call(event))
      unless identity == proposed_stream.stream_id && proposal_matches?(event, selector:)
        return Failure(
          integrity_error(
            :proposal_invalid,
            selector:,
            event_ids: [ event.id ],
            proposed_stream:
          )
        )
      end

      persisted = @event_store.append(proposed_stream, [ event ]).sole
      Success(ResolutionV1.new(identity:, event: persisted, outcome: "created"))
    end

    def criteria(selector)
      Coordinator::Write::GlobalMarkedEventReadCriteria.new(
        stream_context: selector.stream_context,
        stream_name: selector.stream_name,
        event_types: [ selector.event_type ],
        markers: [ selector.marker ],
        maximum_count: 2,
        direction: :asc
      )
    end

    def normalized_identity(identity)
      Coordinator::Write::Types::UuidV7[identity]
    rescue Dry::Types::ConstraintError
      nil
    end

    def persisted_registration_matches?(event, selector:, identity:)
      proposal_matches?(event, selector:) &&
        event.stream.context == selector.stream_context &&
        event.stream.stream_name == selector.stream_name &&
        event.stream.stream_id == identity &&
        event.stream_revision.zero?
    end

    def proposal_matches?(event, selector:)
      event.type == selector.event_type && event.markers.include?(selector.marker)
    end

    def integrity_error(code, selector:, event_ids:, proposed_stream:)
      IntegrityErrorV1.new(
        code:,
        message: integrity_message(code),
        marker: selector.marker,
        event_ids:,
        proposed_stream_id: normalized_identity(proposed_stream.stream_id)
      )
    end

    def integrity_message(code)
      {
        duplicate_registration: "Natural selector resolved more than one registration",
        existing_registration_invalid: "Persisted natural-key registration is inconsistent",
        proposed_stream_occupied: "Proposed UUIDv7 stream is already occupied",
        proposal_invalid: "Proposed registration does not match its selector or UUIDv7 stream"
      }.fetch(code)
    end
  end
end
