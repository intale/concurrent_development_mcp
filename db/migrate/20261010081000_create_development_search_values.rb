# frozen_string_literal: true

class CreateDevelopmentSearchValues < ActiveRecord::Migration[8.1]
  SOURCES = {
    "development_artifacts" => "artifact_id",
    "development_artifact_observations" => "observation_id",
    "agent_choices" => "choice_id",
    "decision_definitions" => "decision_id",
    "coordinator_contexts" => "change_set_id"
  }.freeze

  COLLECTIONS = {
    "development_artifacts" => [ [ "development_artifact.labels", %w[labels] ] ],
    "development_artifact_observations" => [ [ "development_artifact.labels", %w[labels] ] ],
    "agent_choices" => [ [ "agent_choice.warnings", %w[assessment warnings] ] ],
    "decision_definitions" => [
      [ "decision.topic_aliases", %w[definition document topic aliases] ],
      [ "decision.value_items", %w[definition document value items] ],
      [ "decision.scope", %w[definition document scope] ],
      [ "decision.conditions", %w[definition document conditions] ]
    ]
  }.freeze

  def up
    enable_extension "pg_trgm"
    create_table :coordinator_search_values do |table|
      table.text :source_table, null: false
      table.text :source_id, null: false
      table.text :document_id, null: false
      table.text :field, null: false
      table.text :value_path, array: true, null: false
      table.text :value, null: false
      table.datetime :updated_at, precision: 6, null: false
    end
    add_index :coordinator_search_values, %i[source_table source_id field value_path],
              unique: true, name: "idx_search_values_source_path"
    add_index :coordinator_search_values, %i[field updated_at document_id],
              order: { updated_at: :desc }, name: "idx_search_values_field_time"
    execute "CREATE INDEX idx_search_values_text ON coordinator_search_values USING gin (value gin_trgm_ops)"
    create_leaf_function
    create_extractor_function
    create_sync_functions
    SOURCES.each do |table, key|
      execute <<~SQL
        CREATE TRIGGER coordinator_search_values_changed
        AFTER INSERT OR UPDATE OR DELETE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION coordinator_search_values_changed('#{key}')
      SQL
      execute <<~SQL
        CREATE TRIGGER coordinator_search_values_truncated
        AFTER TRUNCATE ON #{table}
        FOR EACH STATEMENT EXECUTE FUNCTION coordinator_search_values_changed('#{key}')
      SQL
    end
  end

  def down
    SOURCES.each_key do |table|
      execute "DROP TRIGGER coordinator_search_values_changed ON #{table}"
      execute "DROP TRIGGER IF EXISTS coordinator_search_values_truncated ON #{table}"
    end
    execute "DROP FUNCTION coordinator_search_values_changed()"
    execute "DROP FUNCTION coordinator_sync_search_values(text, text, jsonb)"
    execute "DROP FUNCTION coordinator_extract_search_values(text, jsonb)"
    execute "DROP FUNCTION coordinator_search_strings(jsonb, text[])"
    drop_table :coordinator_search_values
    # pg_trgm may be used by other read-store indexes; never remove it here.
  end

  private

  def create_leaf_function
    execute <<~SQL
      CREATE FUNCTION coordinator_search_strings(input jsonb, root_path text[])
      RETURNS TABLE(value_path text[], value text)
      LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $function$
        WITH RECURSIVE nodes(node, path) AS (
          SELECT input, root_path
          UNION ALL
          SELECT child.node, nodes.path || child.key
          FROM nodes
          CROSS JOIN LATERAL (
            SELECT item.value AS node, (item.ordinality - 1)::text AS key
            FROM jsonb_array_elements(CASE WHEN jsonb_typeof(nodes.node) = 'array'
              THEN nodes.node ELSE '[]'::jsonb END) WITH ORDINALITY AS item(value, ordinality)
            UNION ALL
            SELECT item.value, item.key
            FROM jsonb_each(CASE WHEN jsonb_typeof(nodes.node) = 'object'
              THEN nodes.node ELSE '{}'::jsonb END) AS item(key, value)
          ) AS child
        )
        SELECT path, node #>> '{}' FROM nodes WHERE jsonb_typeof(node) = 'string'
      $function$
    SQL
  end

  def create_extractor_function
    arms = COLLECTIONS.flat_map do |table, fields|
      fields.map do |field, path|
        <<~SQL
          SELECT source ->> '#{SOURCES.fetch(table)}', '#{field}', leaf.value_path, leaf.value
          FROM coordinator_search_strings(source #> '{#{path.join(',')}}',
            ARRAY[#{path.map { connection.quote(_1) }.join(',')}]) AS leaf
          WHERE source_table = '#{table}'
        SQL
      end
    end
    arms << <<~SQL
      SELECT source ->> 'choice_id', 'agent_choice.alternative_summary',
        ARRAY['alternatives', (alternative.ordinality - 1)::text, 'summary'], alternative.value ->> 'summary'
      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(source -> 'alternatives') = 'array'
        THEN source -> 'alternatives' ELSE '[]'::jsonb END)
        WITH ORDINALITY AS alternative(value, ordinality)
      WHERE source_table = 'agent_choices' AND jsonb_typeof(alternative.value -> 'summary') = 'string'
    SQL
    arms << <<~SQL
      SELECT work_item.value ->> 'work_item_id', field.selector, leaf.value_path, leaf.value
      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(source #> '{document,work_items}') = 'array'
        THEN source #> '{document,work_items}' ELSE '[]'::jsonb END)
        WITH ORDINALITY AS work_item(value, ordinality)
      CROSS JOIN LATERAL (VALUES
        ('work_item.goal', 'goal'), ('work_item.acceptance_criteria', 'acceptance_criteria')
      ) AS field(selector, key)
      CROSS JOIN LATERAL coordinator_search_strings(work_item.value -> field.key,
        ARRAY['document', 'work_items', (work_item.ordinality - 1)::text, field.key]) AS leaf
      WHERE source_table = 'coordinator_contexts' AND work_item.value ->> 'work_item_id' IS NOT NULL
    SQL
    execute <<~SQL
      CREATE FUNCTION coordinator_extract_search_values(source_table text, source jsonb)
      RETURNS TABLE(document_id text, field text, value_path text[], value text)
      LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $function$
        #{arms.join("\nUNION ALL\n")}
      $function$
    SQL
  end

  def create_sync_functions
    execute <<~SQL
      CREATE FUNCTION coordinator_sync_search_values(owner_table text, owner_id text, source jsonb)
      RETURNS void LANGUAGE plpgsql AS $function$
      BEGIN
        DELETE FROM coordinator_search_values WHERE source_table = owner_table AND source_id = owner_id;
        INSERT INTO coordinator_search_values(source_table, source_id, document_id, field, value_path, value, updated_at)
        SELECT owner_table, owner_id, leaf.document_id, leaf.field, leaf.value_path, leaf.value,
          (source ->> 'updated_at')::timestamp
        FROM coordinator_extract_search_values(owner_table, source) AS leaf;
      END
      $function$;

      CREATE FUNCTION coordinator_search_values_changed()
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
  end
end
