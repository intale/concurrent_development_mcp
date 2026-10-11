# frozen_string_literal: true

class OptimizeDevelopmentSearchValueMaintenance < ActiveRecord::Migration[8.1]
  SOURCES = {
    "development_artifacts" => "artifact_id",
    "development_artifact_observations" => "observation_id",
    "agent_choices" => "choice_id",
    "decision_definitions" => "decision_id",
    "coordinator_contexts" => "change_set_id"
  }.freeze

  def up
    create_selected_inputs
    execute <<~SQL
      CREATE OR REPLACE FUNCTION coordinator_sync_search_values(owner_table text, owner_id text, source jsonb)
      RETURNS void LANGUAGE plpgsql AS $function$
      BEGIN
        DELETE FROM coordinator_search_values AS stored
        WHERE stored.source_table = owner_table AND stored.source_id = owner_id
          AND NOT EXISTS (
            SELECT 1 FROM coordinator_extract_search_values(owner_table, source) AS desired
            WHERE desired.field = stored.field AND desired.value_path = stored.value_path
          );

        INSERT INTO coordinator_search_values AS stored
          (source_table, source_id, document_id, field, value_path, value, updated_at)
        SELECT owner_table, owner_id, leaf.document_id, leaf.field, leaf.value_path, leaf.value,
          (source ->> 'updated_at')::timestamp
        FROM coordinator_extract_search_values(owner_table, source) AS leaf
        ON CONFLICT (source_table, source_id, field, value_path) DO UPDATE
          SET document_id = EXCLUDED.document_id, value = EXCLUDED.value, updated_at = EXCLUDED.updated_at
          WHERE (stored.document_id, stored.value, stored.updated_at)
            IS DISTINCT FROM (EXCLUDED.document_id, EXCLUDED.value, EXCLUDED.updated_at);
      END
      $function$;

      CREATE OR REPLACE FUNCTION coordinator_search_values_changed()
      RETURNS trigger LANGUAGE plpgsql AS $function$
      DECLARE
        old_input jsonb;
        new_input jsonb;
        old_id text;
        new_id text;
        source_time timestamp;
      BEGIN
        IF TG_OP = 'TRUNCATE' THEN
          DELETE FROM coordinator_search_values WHERE source_table = TG_TABLE_NAME;
          RETURN NULL;
        END IF;
        IF TG_OP = 'DELETE' THEN
          CASE TG_TABLE_NAME
            #{SOURCES.map { |table, key| "WHEN '#{table}' THEN old_id := OLD.#{key};" }.join("\n")}
          END CASE;
          DELETE FROM coordinator_search_values
          WHERE source_table = TG_TABLE_NAME AND source_id = old_id;
          RETURN NULL;
        END IF;

        new_input := coordinator_search_input(NEW);
        new_id := new_input ->> TG_ARGV[0];
        source_time := (new_input ->> 'updated_at')::timestamp;
        IF TG_OP = 'UPDATE' THEN
          old_input := coordinator_search_input(OLD);
          old_id := old_input ->> TG_ARGV[0];
          IF old_id IS DISTINCT FROM new_id THEN
            DELETE FROM coordinator_search_values
            WHERE source_table = TG_TABLE_NAME AND source_id = old_id;
          ELSIF (old_input - 'updated_at') IS NOT DISTINCT FROM (new_input - 'updated_at') THEN
            UPDATE coordinator_search_values SET updated_at = source_time
            WHERE source_table = TG_TABLE_NAME AND source_id = new_id
              AND updated_at IS DISTINCT FROM source_time;
            RETURN NULL;
          END IF;
        END IF;
        PERFORM coordinator_sync_search_values(TG_TABLE_NAME, new_id, new_input);
        RETURN NULL;
      END
      $function$
    SQL
  end

  def down
    execute <<~SQL
      CREATE OR REPLACE FUNCTION coordinator_sync_search_values(owner_table text, owner_id text, source jsonb)
      RETURNS void LANGUAGE plpgsql AS $function$
      BEGIN
        DELETE FROM coordinator_search_values WHERE source_table = owner_table AND source_id = owner_id;
        INSERT INTO coordinator_search_values(source_table, source_id, document_id, field, value_path, value, updated_at)
        SELECT owner_table, owner_id, leaf.document_id, leaf.field, leaf.value_path, leaf.value,
          (source ->> 'updated_at')::timestamp
        FROM coordinator_extract_search_values(owner_table, source) AS leaf;
      END
      $function$;

      CREATE OR REPLACE FUNCTION coordinator_search_values_changed()
      RETURNS trigger LANGUAGE plpgsql AS $function$
      BEGIN
        IF TG_OP = 'TRUNCATE' THEN
          DELETE FROM coordinator_search_values WHERE source_table = TG_TABLE_NAME;
          RETURN NULL;
        END IF;
        IF TG_OP = 'DELETE' THEN
          DELETE FROM coordinator_search_values
          WHERE source_table = TG_TABLE_NAME AND source_id = to_jsonb(OLD) ->> TG_ARGV[0];
        ELSIF TG_OP = 'UPDATE' THEN
          IF (to_jsonb(OLD) ->> TG_ARGV[0]) IS DISTINCT FROM (to_jsonb(NEW) ->> TG_ARGV[0]) THEN
            DELETE FROM coordinator_search_values
            WHERE source_table = TG_TABLE_NAME AND source_id = to_jsonb(OLD) ->> TG_ARGV[0];
          END IF;
        END IF;
        IF TG_OP <> 'DELETE' THEN
          PERFORM coordinator_sync_search_values(TG_TABLE_NAME, to_jsonb(NEW) ->> TG_ARGV[0], to_jsonb(NEW));
        END IF;
        RETURN NULL;
      END
      $function$
    SQL
    SOURCES.each_key { execute "DROP FUNCTION coordinator_search_input(#{_1})" }
  end

  private

  def create_selected_inputs
    %w[development_artifacts development_artifact_observations].each do |table|
      create_input(table, "'labels', (source).labels")
    end
    create_input("agent_choices", <<~SQL)
      'assessment', jsonb_build_object('warnings', (source).assessment -> 'warnings'),
      'alternatives', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('summary', item.value -> 'summary') ORDER BY item.ordinality)
        FROM jsonb_array_elements(CASE WHEN jsonb_typeof((source).alternatives) = 'array'
          THEN (source).alternatives ELSE '[]'::jsonb END) WITH ORDINALITY AS item(value, ordinality)
      ), '[]'::jsonb)
    SQL
    create_input("decision_definitions", <<~SQL)
      'definition', jsonb_build_object('document', jsonb_build_object(
        'topic', jsonb_build_object('aliases', (source).definition #> '{document,topic,aliases}'),
        'value', jsonb_build_object('items', (source).definition #> '{document,value,items}'),
        'scope', (source).definition #> '{document,scope}',
        'conditions', (source).definition #> '{document,conditions}'
      ))
    SQL
    create_input("coordinator_contexts", <<~SQL)
      'document', jsonb_build_object('work_items', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'work_item_id', item.value -> 'work_item_id',
          'goal', item.value -> 'goal',
          'acceptance_criteria', item.value -> 'acceptance_criteria'
        ) ORDER BY item.ordinality)
        FROM jsonb_array_elements(CASE WHEN jsonb_typeof((source).document -> 'work_items') = 'array'
          THEN (source).document -> 'work_items' ELSE '[]'::jsonb END)
          WITH ORDINALITY AS item(value, ordinality)
      ), '[]'::jsonb))
    SQL
  end

  def create_input(table, collections)
    key = SOURCES.fetch(table)
    execute <<~SQL
      CREATE FUNCTION coordinator_search_input(source #{table})
      RETURNS jsonb LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $function$
        SELECT jsonb_build_object('#{key}', (source).#{key}, 'updated_at', (source).updated_at,
          #{collections})
      $function$
    SQL
  end
end
