# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class DevelopmentArtifacts
      RELATION_OBSERVED_SEQUENCE_SQL = "development_artifact_relations.observed_sequence"
      INITIAL_OBSERVATION_FACT_ROLES = %w[created scope title kind source content].freeze
      SUPERSESSION_OBSERVED_SEQUENCE_SQL =
        "development_artifact_relation_supersessions.observed_sequence"
      CURRENT_OBSERVED_SEQUENCE_SQL =
        "GREATEST(#{RELATION_OBSERVED_SEQUENCE_SQL}, " \
        "COALESCE(#{SUPERSESSION_OBSERVED_SEQUENCE_SQL}, 0))"
      OBSERVATION_TABLE_SQL = "development_artifact_observations"

      def initialize(
        relation_registry: Coordinator::Shared::DevelopmentArtifactRelationRegistry.new,
        follow_action: DevelopmentArtifactRelationFollowAction.new
      )
        @relation_registry = relation_registry
        @follow_action = follow_action
      end

      def fetch(artifact_id, observation_id: nil)
        artifact = Coordinator::Read::DevelopmentArtifact.find_by(artifact_id:)
        return unless artifact

        observations = complete_observations.where(artifact_id:)
        observations = observations.where(observation_id:) if observation_id
        observation = observations.order(observed_global_position: :desc, observation_id: :desc).first
        observation && build_view(artifact, observation)
      end

      def fetch_content(artifact_id, observation_id: nil)
        if observation_id
          observation = Coordinator::Read::DevelopmentArtifactObservation.find_by(
            observation_id:, artifact_id:
          )
          return unless observation&.content_encoding

          return build_content(observation)
        end

        record = Coordinator::Read::DevelopmentArtifact.find_by(artifact_id:)
        return unless record&.content_encoding

        build_content(record)
      end

      def page(query)
        relation = complete_observations.includes(:artifact)
        relation = relation.where(scope: query.scope) if query.scope
        relation = relation.where(kind: query.kind) if query.kind
        relation = relation.where(source_kind: query.source_kind) if query.source_kind
        if query.labels.any?
          relation = relation.where(
            "#{OBSERVATION_TABLE_SQL}.labels @> ?::jsonb",
            JSON.generate(query.labels)
          )
        end
        relation = relation.where(
          artifact_id: relation_target_source_ids(query)
        ) if query.relation_target_kind
        if query.after_global_position
          relation = relation.where(
            "#{OBSERVATION_TABLE_SQL}.current_global_position > ?",
            query.after_global_position
          )
        end

        rows = relation
          .order("#{OBSERVATION_TABLE_SQL}.current_global_position", "#{OBSERVATION_TABLE_SQL}.observation_id")
          .page(1)
          .per(query.limit + 1)
          .to_a
        has_more = rows.length > query.limit
        visible_rows = rows.first(query.limit)
        counts = relationship_capacity_counts(visible_rows.map(&:artifact_id))
        items = visible_rows.map do |record|
          build_summary(record, record.artifact, relationship_counts: counts.fetch(record.artifact_id))
        end
        DevelopmentArtifactPageV1.new(
          items:,
          next_global_position: has_more ? rows.fetch(query.limit - 1).current_global_position : nil,
          has_more:
        )
      end

      def event_time_page(query)
        relation = complete_observations.includes(:artifact)
        relation = relation.where(scope: query.scope) if query.scope
        relation = relation.where(kind: query.kind) if query.kind
        relation = relation.where(source_kind: query.source_kind) if query.source_kind
        if query.labels.any?
          relation = relation.where(
            "#{OBSERVATION_TABLE_SQL}.labels @> ?::jsonb",
            JSON.generate(query.labels)
          )
        end
        if query.after_updated_at
          comparator = query.sort == "oldest_first" ? ">" : "<"
          relation = relation.where(
            "#{OBSERVATION_TABLE_SQL}.updated_at #{comparator} :updated_at OR " \
            "(#{OBSERVATION_TABLE_SQL}.updated_at = :updated_at AND " \
            "#{OBSERVATION_TABLE_SQL}.observation_id #{comparator} :observation_id)",
            updated_at: query.after_updated_at,
            observation_id: query.after_observation_id
          )
        end
        direction = query.sort == "oldest_first" ? "ASC" : "DESC"
        rows = relation
          .order("#{OBSERVATION_TABLE_SQL}.updated_at #{direction}", "#{OBSERVATION_TABLE_SQL}.observation_id #{direction}")
          .limit(query.first + 1)
          .to_a
        has_more = rows.length > query.first
        visible_rows = rows.first(query.first)
        counts = relationship_capacity_counts(visible_rows.map(&:artifact_id))
        items = visible_rows.map do |record|
          build_summary(record, record.artifact, relationship_counts: counts.fetch(record.artifact_id))
        end
        last = visible_rows.last

        Coordinator::Read::Web::KnowledgeBrowserV1::ArtifactPage.new(
          items:,
          next_cursor: has_more ? Coordinator::Read::Web::KnowledgeBrowserV1::ArtifactCursor.new(
            updated_at: last.updated_at.utc.iso8601(6),
            observation_id: last.observation_id
          ) : nil,
          has_more:
        )
      end

      def relation_page(query)
        cursor = query.cursor
        base = navigation_scope(query)
        upper = cursor.through_observed_sequence || maximum_observed_sequence(
          base,
          include_superseded: query.include_superseded
        )
        observed_sequence_sql = observed_sequence_at(upper)
        window = base.where(
          "#{observed_sequence_sql} > ? AND #{observed_sequence_sql} <= ?",
          cursor.after_observed_sequence,
          upper
        )
        window = active_at(window, upper) unless query.include_superseded
        window = after_declaration(window, cursor)
        rows = window
          .select(
            "development_artifact_relations.*",
            "#{observed_sequence_sql} AS navigation_sequence",
            "#{superseded_at(upper)} AS navigation_superseded"
          )
          .includes(:supersession)
          .order(:declared_global_position, :relation_id)
          .limit(query.limit + 1)
          .to_a
        window_has_more = rows.length > query.limit
        visible_rows = rows.first(query.limit)
        summaries = summaries_for(query.artifact_id, visible_rows)
        items = visible_rows.map { build_navigation_relation(_1, query.artifact_id, summaries) }
        continuation = continuation_cursor(
          cursor:,
          upper:,
          items: visible_rows,
          window_has_more:
        )
        has_more = window_has_more || maximum_observed_sequence(
          base,
          include_superseded: query.include_superseded
        ) > upper

        DevelopmentArtifactRelationPageV1.new(
          artifact: summaries[query.artifact_id],
          items:,
          continuation_cursor: continuation,
          has_more:
        )
      end

      def locator_page(query)
        cursor = query.cursor
        base = exact_locator_scope(query)
        resolution = locator_resolution(base)
        upper = cursor.through_observed_sequence || maximum_artifact_observed_sequence(base)
        window = base.where(
          "#{OBSERVATION_TABLE_SQL}.observed_sequence > ? AND " \
            "#{OBSERVATION_TABLE_SQL}.observed_sequence <= ?",
          cursor.after_observed_sequence,
          upper
        )
        window = after_observation_change(window, cursor)
        rows = window
          .includes(:artifact)
          .order("#{OBSERVATION_TABLE_SQL}.current_global_position", "#{OBSERVATION_TABLE_SQL}.observation_id")
          .limit(query.limit + 1)
          .to_a
        window_has_more = rows.length > query.limit
        visible_rows = rows.first(query.limit)
        counts = relationship_capacity_counts(visible_rows.map(&:artifact_id))
        items = visible_rows.map do |record|
          build_summary(record, record.artifact, relationship_counts: counts.fetch(record.artifact_id))
        end
        continuation = locator_continuation_cursor(
          cursor:,
          upper:,
          items: visible_rows,
          window_has_more:
        )
        has_more = window_has_more || maximum_artifact_observed_sequence(base) > upper

        DevelopmentArtifactLocatorPageV1.new(
          resolution:,
          items:,
          continuation_cursor: continuation,
          has_more:
        )
      end

      private

      def exact_locator_scope(query)
        relation = complete_observations.where(
          scope: query.scope,
          source_kind: query.source_kind,
          source_locator: query.locator
        )
        return relation unless query.revision_specified

        relation.where(source_revision: query.source_revision)
      end

      def locator_resolution(relation)
        case relation.limit(2).pluck(:observation_id).length
        when 0 then "absent"
        when 1 then "unique"
        else "ambiguous"
        end
      end

      def maximum_artifact_observed_sequence(relation)
        relation.maximum(Arel.sql("#{OBSERVATION_TABLE_SQL}.observed_sequence")) || 0
      end

      def after_observation_change(relation, cursor)
        return relation unless cursor.after_current_global_position

        relation.where(
          "(#{OBSERVATION_TABLE_SQL}.current_global_position, " \
            "#{OBSERVATION_TABLE_SQL}.observation_id) > (?, ?)",
          cursor.after_current_global_position,
          cursor.after_observation_id
        )
      end

      def locator_continuation_cursor(cursor:, upper:, items:, window_has_more:)
        if window_has_more
          last = items.last
          return DevelopmentArtifactLocatorPageV1::Cursor.new(
            after_observed_sequence: cursor.after_observed_sequence,
            through_observed_sequence: upper,
            after_current_global_position: last.current_global_position,
            after_observation_id: last.observation_id
          )
        end

        DevelopmentArtifactLocatorPageV1::Cursor.new(
          after_observed_sequence: upper,
          through_observed_sequence: nil,
          after_current_global_position: nil,
          after_observation_id: nil
        )
      end

      def navigation_scope(query)
        relation = Coordinator::Read::DevelopmentArtifactRelation.left_outer_joins(:supersession)
        relation = direction_scope(relation, query)
        relation = relation.where(relation: query.relation) if query.relation
        relation
      end

      def direction_scope(relation, query)
        table = Coordinator::Read::DevelopmentArtifactRelation.table_name
        outgoing = "#{table}.source_artifact_id = :artifact_id"
        incoming = "#{table}.target_kind = 'artifact' AND #{table}.target_id = :artifact_id"
        predicate =
          case query.direction
          when "outgoing" then outgoing
          when "incoming" then incoming
          else "(#{outgoing}) OR (#{incoming})"
          end
        relation.where(predicate, artifact_id: query.artifact_id)
      end

      def maximum_observed_sequence(relation, include_superseded:)
        relation = active_at(relation, nil) unless include_superseded
        relation.maximum(Arel.sql(CURRENT_OBSERVED_SEQUENCE_SQL)) || 0
      end

      def observed_sequence_at(upper)
        "CASE WHEN #{superseded_at(upper)} " \
          "THEN #{SUPERSESSION_OBSERVED_SEQUENCE_SQL} " \
          "ELSE #{RELATION_OBSERVED_SEQUENCE_SQL} END"
      end

      def superseded_at(upper)
        return "#{SUPERSESSION_OBSERVED_SEQUENCE_SQL} IS NOT NULL" unless upper

        "#{SUPERSESSION_OBSERVED_SEQUENCE_SQL} IS NOT NULL AND " \
          "#{SUPERSESSION_OBSERVED_SEQUENCE_SQL} <= #{Integer(upper)}"
      end

      def active_at(relation, upper)
        relation.where("NOT (#{superseded_at(upper)})")
      end

      def after_declaration(relation, cursor)
        return relation unless cursor.after_declared_global_position

        relation.where(
          "(development_artifact_relations.declared_global_position, " \
          "development_artifact_relations.relation_id) > (?, ?)",
          cursor.after_declared_global_position,
          cursor.after_relation_id
        )
      end

      def continuation_cursor(cursor:, upper:, items:, window_has_more:)
        if window_has_more
          last = items.last
          return DevelopmentArtifactRelationPageV1::Cursor.new(
            after_observed_sequence: cursor.after_observed_sequence,
            through_observed_sequence: upper,
            after_declared_global_position: last.declared_global_position,
            after_relation_id: last.relation_id
          )
        end

        DevelopmentArtifactRelationPageV1::Cursor.new(
          after_observed_sequence: upper,
          through_observed_sequence: nil,
          after_declared_global_position: nil,
          after_relation_id: nil
        )
      end

      def relation_target_source_ids(query)
        active_relations.where(
          target_kind: query.relation_target_kind,
          target_id: query.relation_target_id
        ).select(:source_artifact_id)
      end

      def build_view(record, observation)
        relations = Coordinator::Read::DevelopmentArtifactRelation
          .where(source_artifact_id: record.artifact_id)
          .includes(:supersession)
          .order(:declared_global_position, :relation_id)
          .to_a
        summaries = summaries_for(record.artifact_id, relations)
        summaries[record.artifact_id] = build_summary(observation, record)
        DevelopmentArtifactViewV1.new(
          artifact: summaries.fetch(record.artifact_id),
          relationships: relations.map do |relation|
            build_navigation_relation(relation, record.artifact_id, summaries)
          end
        )
      end

      def build_summary(observation, artifact, relationship_counts: nil)
        counts = relationship_counts || { active: artifact.active_relations_number, lifetime: artifact.lifetime_relations_number }
        content = observation.content_encoding ? observation : artifact
        DevelopmentArtifactSummaryV1.new(
          artifact_id: artifact.artifact_id,
          stream_revision: artifact.stream_revision,
          observation_id: observation.observation_id,
          scope: observation.scope,
          title: observation.title,
          kind: observation.kind,
          labels: observation.labels,
          media_type: content.content_media_type,
          encoding: content.content_encoding,
          content_sha256: content.content_sha256,
          byte_size: content.content_byte_size,
          source: provenance(observation),
          classification_revision: observation.classification_revision,
          classification_reason: observation.classification_reason,
          relationship_count: counts.fetch(:active),
          relationship_capacity: relationship_capacity(counts),
          captured: evidence(artifact, "captured"),
          observed: evidence(observation, "observed"),
          classified: evidence(observation, "classified")
        )
      end

      def build_content(record)
        view = record.content_encoding == "utf-8" ?
          DevelopmentArtifactTextContentViewV2 : DevelopmentArtifactBinaryContentViewV2
        content_attribute = record.content_encoding == "utf-8" ?
          { text: record.content_text } : { base64: record.content_base64 }
        view.new(
          artifact_id: record.artifact_id,
          encoding: record.content_encoding,
          media_type: record.content_media_type,
          **content_attribute,
          content_sha256: record.content_sha256,
          byte_size: record.content_byte_size
        )
      end

      def build_navigation_relation(record, artifact_id, summaries)
        direction = record.source_artifact_id == artifact_id ? "outgoing" : "incoming"
        peer_kind = direction == "outgoing" ? record.target_kind : "artifact"
        peer_id = direction == "outgoing" ? record.target_id : record.source_artifact_id
        supersession = visible_supersession(record)
        definition = @relation_registry.fetch(record.relation)
        target = relation_target(record)
        DevelopmentArtifactRelationViewV1.new(
          relation_id: record.relation_id,
          source_artifact_id: record.source_artifact_id,
          relation: record.relation,
          display_relation: direction == "outgoing" ? definition.relation : definition.inverse,
          inverse_relation: definition.inverse,
          transitive: definition.transitive,
          supersedable: definition.supersedable,
          target:,
          attributes: Coordinator::Write::DevelopmentArtifacts::RelationAttributesV1.new(
            path: record.path,
            fragment: record.fragment,
            normalized_locator: record.normalized_locator
          ),
          direction:,
          peer_kind:,
          peer_id:,
          peer_artifact: peer_kind == "artifact" ? summaries[peer_id] : nil,
          status: supersession ? "superseded" : "active",
          observed_sequence: record[:navigation_sequence] || effective_sequence(record),
          declared: evidence(record, "declared"),
          replacement_relation_id: supersession&.replacement_relation_id,
          supersession_reason: supersession&.reason,
          superseded: supersession && evidence(supersession, "superseded"),
          follow_action: @follow_action.call(
            direction:,
            source_artifact_id: record.source_artifact_id,
            target:
          )
        )
      end

      def effective_sequence(record)
        record.supersession&.observed_sequence || record.observed_sequence
      end

      def relation_target(record)
        attributes = {
          kind: record.target_kind,
          id: record.target_id,
          status: record.target_status,
          name: record.target_name,
          scope: record.target_scope
        }
        case record.target_kind
        when "skill"
          skill = Coordinator::Read::Skill.find_by(skill_id: record.target_id)
          attributes[:name] ||= skill&.name
          attributes[:scope] ||= skill&.scope
        when "repository"
          repository = Coordinator::Read::Repository.find_by(repository_id: record.target_id)
          attributes[:name] ||= repository_key(repository)
          attributes[:scope] ||= repository&.scope
        end
        Coordinator::Write::DevelopmentArtifacts::RelationTargetV1.new(**attributes)
      end

      def repository_key(repository)
        repository&.registered_markers&.find { _1.start_with?("repository-key:") }
          &.delete_prefix("repository-key:")
      end

      def visible_supersession(record)
        return record.supersession unless record.has_attribute?("navigation_superseded")

        record[:navigation_superseded] ? record.supersession : nil
      end

      def summaries_for(artifact_id, relations)
        peer_ids = relations.filter_map do |relation|
          if relation.source_artifact_id == artifact_id
            relation.target_id if relation.target_kind == "artifact"
          else
            relation.source_artifact_id
          end
        end
        ids = ([ artifact_id ] + peer_ids).uniq
        observations = complete_observations
          .where(artifact_id: ids)
          .includes(:artifact)
          .order("#{OBSERVATION_TABLE_SQL}.observed_global_position", "#{OBSERVATION_TABLE_SQL}.observation_id")
          .to_a
          .index_by(&:artifact_id)
        counts = relationship_capacity_counts(ids)
        observations.transform_values do |observation|
          build_summary(
            observation,
            observation.artifact,
            relationship_counts: counts.fetch(observation.artifact_id)
          )
        end
      end

      def relationship_capacity_counts(artifact_ids)
        Coordinator::Read::DevelopmentArtifact.where(artifact_id: artifact_ids.uniq)
          .pluck(:artifact_id, :active_relations_number, :lifetime_relations_number)
          .to_h { |id, active, lifetime| [ id, { active:, lifetime: } ] }
      end

      def relationship_capacity(counts)
        active = counts.fetch(:active)
        lifetime = counts.fetch(:lifetime)
        DevelopmentArtifactRelationshipCapacityV1.new(
          active_count: active,
          active_limit: Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT,
          active_remaining: [
            Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT - active,
            0
          ].max,
          lifetime_count: lifetime,
          lifetime_limit: Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT,
          lifetime_remaining: [
            Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT - lifetime,
            0
          ].max
        )
      end

      def complete_observations
        relation = Coordinator::Read::DevelopmentArtifactObservation.joins(:artifact)
        %i[
          observed_event artifact_id scope title kind source_kind source_locator
          source_observed_at source_collector classified_event classified_actor
          classified_global_position classified_at_domain classified_at_store
        ].each { |column| relation = relation.where.not(column => nil) }
        %i[content_encoding content_media_type content_sha256 content_byte_size].each do |column|
          relation = relation.where.not(development_artifacts: { column => nil })
        end
        granular_requirements = INITIAL_OBSERVATION_FACT_ROLES.map do |role|
          escaped_role = role.gsub("'", "''")
          "EXISTS (SELECT 1 FROM development_artifact_observation_fact_links " \
            "WHERE development_artifact_observation_fact_links.observation_id = " \
            "development_artifact_observations.observation_id AND " \
            "development_artifact_observation_fact_links.role = '#{escaped_role}')"
        end.join(" AND ")
        completeness_sql = [
          "development_artifact_observations.content_encoding IS NOT NULL AND ",
          "development_artifact_observations.content_media_type IS NOT NULL AND ",
          "development_artifact_observations.content_sha256 IS NOT NULL AND ",
          "development_artifact_observations.content_byte_size IS NOT NULL AND ",
          granular_requirements
        ].join
        relation.where(completeness_sql)
      end

      def active_relations
        Coordinator::Read::DevelopmentArtifactRelation.where.not(
          relation_id: Coordinator::Read::DevelopmentArtifactRelationSupersession
            .select(:superseded_relation_id)
        )
      end

      def provenance(record)
        DevelopmentArtifactProvenanceV1.new(
          kind: record.source_kind,
          locator: record.source_locator,
          revision: record.source_revision,
          observed_at: record.source_observed_at.utc.iso8601(6),
          collector: record.source_collector
        )
      end

      def evidence(record, prefix)
        DevelopmentArtifactEventEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(record.public_send("#{prefix}_event"))),
          actor: AttributedActorV1.new(symbolize(record.public_send("#{prefix}_actor"))),
          markers: record.public_send("#{prefix}_markers"),
          metadata: record.public_send("#{prefix}_metadata"),
          global_position: record.public_send("#{prefix}_global_position"),
          occurred_at: record.public_send("#{prefix}_at_domain").utc.iso8601(6),
          persisted_at: record.public_send("#{prefix}_at_store").utc.iso8601(6),
          causation_id: record.public_send("#{prefix}_causation_id"),
          correlation_id: record.public_send("#{prefix}_correlation_id")
        )
      end

      def symbolize(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, symbolize(nested) ] }
        when Array then value.map { symbolize(_1) }
        else value
        end
      end
    end
  end
end
