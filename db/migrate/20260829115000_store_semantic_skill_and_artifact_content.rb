# frozen_string_literal: true

class StoreSemanticSkillAndArtifactContent < ActiveRecord::Migration[8.1]
  def up
    add_column :skill_assets, :content_encoding, :string
    add_column :skill_assets, :content_text, :text
    change_column_null :skill_assets, :content_base64, true
    execute <<~SQL.squish
      UPDATE skill_assets
      SET content_encoding = 'binary'
    SQL
    change_column_null :skill_assets, :content_encoding, false

    add_column :development_artifacts, :content_text, :text
    change_column_null :development_artifacts, :content_base64, true
    execute <<~SQL.squish
      UPDATE development_artifacts
      SET content_text = convert_from(decode(content_base64, 'base64'), 'UTF8'),
          content_base64 = NULL
      WHERE content_encoding = 'utf-8'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE development_artifacts
      SET content_base64 = encode(convert_to(content_text, 'UTF8'), 'base64')
      WHERE content_encoding = 'utf-8'
    SQL
    change_column_null :development_artifacts, :content_base64, false
    remove_column :development_artifacts, :content_text

    change_column_null :skill_assets, :content_base64, false
    remove_column :skill_assets, :content_text
    remove_column :skill_assets, :content_encoding
  end
end
