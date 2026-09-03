# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class AssetStateV1 < Value
      attribute :asset_id, Types::UuidV7
      attribute :path, Types::SkillAssetPath.optional
      # The event metadata selects the representation: UTF-8 text is stored as
      # text and binary content as canonical Base64.
      attribute :content, (Types::ContentText | Types::ContentBase64).optional
      attribute :executable, Types::Bool.optional

      def self.initial(asset_id:)
        new(asset_id:, path: nil, content: nil, executable: nil)
      end

      def self.reduce(events)
        state = nil
        events.each do |event|
          case event
          when Events::SkillAssetCreatedV1
            state = initial(asset_id: event.asset_id)
          when Events::SkillAssetPathDefinedV1
            state = state.class.new(**state.to_h, path: event.path)
          when Events::SkillAssetContentDefinedV1
            state = state.class.new(**state.to_h, content: event.content)
          when Events::SkillAssetExecutabilityDefinedV1
            state = state.class.new(**state.to_h, executable: event.executable)
          end
        end
        state
      end
    end
  end
end
