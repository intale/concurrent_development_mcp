# frozen_string_literal: true

module Coordinator::Read::Projections
  module Batches
    # A batch records changes, not a replacement snapshot of an existing row.
    # Inserts are separate so a partial update needs no missing required fields.
    class ColumnPatches
      attr_reader :identity_columns

      def initialize(identity_columns:)
        @identity_columns = identity_columns.dup.freeze
        @inserts = {}
        @updates = {}
      end

      def insert(attributes)
        @inserts[identity(attributes)] ||= attributes.dup
        nil
      end

      def assign(attributes)
        key = identity(attributes)
        (@updates[key] ||= {}).merge!(attributes)
        nil
      end

      def touch(attributes, time:)
        current = @updates[identity(attributes)]&.fetch(:updated_at, nil)
        assign(attributes.merge(updated_at: current && current > time ? current : time))
      end

      def inserts
        @inserts.values
      end

      def update_groups
        @updates.values
          .group_by { (_1.keys - identity_columns).sort }
          .reject { |columns, _rows| columns.empty? }
          .map { |columns, rows| UpdateGroup.new(columns:, rows:) }
      end

      def empty?
        @inserts.empty? && update_groups.empty?
      end

      private

      def identity(attributes)
        attributes.values_at(*identity_columns)
      end
    end
  end
end
