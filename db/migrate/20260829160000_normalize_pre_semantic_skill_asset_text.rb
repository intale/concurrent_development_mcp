# frozen_string_literal: true

class NormalizePreSemanticSkillAssetText < ActiveRecord::Migration[8.1]
  class MigrationSkillAsset < ActiveRecord::Base
    self.table_name = "skill_assets"
  end

  def up
    binary_assets.find_each do |asset|
      bytes = canonical_base64_bytes(asset.content_base64)
      next unless bytes

      text = bytes.dup.force_encoding(Encoding::UTF_8)
      next unless text.valid_encoding?

      asset.update_columns(
        content_encoding: "utf-8",
        content_text: text,
        content_base64: nil,
        updated_at: Time.now.utc
      )
    end
  end

  def down
    MigrationSkillAsset.where(content_encoding: "utf-8", content_base64: nil).where.not(content_text: nil).find_each do |asset|
      asset.update_columns(
        content_encoding: "binary",
        content_text: nil,
        content_base64: [ asset.content_text.b ].pack("m0"),
        updated_at: Time.now.utc
      )
    end
  end

  private

  def binary_assets
    MigrationSkillAsset.where(content_encoding: "binary").where.not(content_base64: nil)
  end

  def canonical_base64_bytes(value)
    bytes = value.unpack1("m0")
    bytes if [ bytes ].pack("m0") == value
  rescue ArgumentError
    nil
  end
end
