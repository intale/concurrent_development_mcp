# frozen_string_literal: true

# Concrete immutable source fixtures, not commands or an EventStore replacement.
# Keeping their wire data unchanged lets direct projector specs demonstrate that
# incoming facts are trusted even when event contract metadata is not consulted.
class TrustedProjectionEventFactory
  def build(type:, data:, metadata:, markers: [])
    PgEventstore::Event.new(type:, data: JSON.parse(JSON.generate(data)), metadata:, markers:)
  end
end
