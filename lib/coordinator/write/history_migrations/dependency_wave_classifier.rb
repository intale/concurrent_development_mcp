# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DependencyWaveClassifier
      CREATION_WAVE = 0
      DEFINITION_WAVE = 1
      RELATION_WAVE = 2
      TERMINAL_WAVE = 3

      RELATION_PATTERNS = %w[
        Added
        Anchored
        Assigned
        DependencyDeclared
        DerivedFrom
        Enqueued
        HeadChanged
        HeadRegistered
        Linked
        PartitionAdvanced
        RelationDeclared
        WorkIntentionDeclared
      ].freeze
      TERMINAL_PATTERNS = %w[
        Acquired
        Activated
        Cancelled
        Completed
        Denied
        Expired
        Failed
        Granted
        Invalidated
        Published
        Rejected
        Released
        Satisfied
        Selected
        Started
        Succeeded
        Superseded
        Waived
        Withdrawn
      ].freeze

      def call(target_event_type:, target_revision:, previous_wave: nil)
        [ minimum_wave(target_event_type, target_revision), previous_wave || CREATION_WAVE ].max
      end

      private

      def minimum_wave(event_type, revision)
        return TERMINAL_WAVE if TERMINAL_PATTERNS.any? { event_type.include?(_1) }
        return RELATION_WAVE if RELATION_PATTERNS.any? { event_type.include?(_1) }
        return CREATION_WAVE if revision.zero?

        DEFINITION_WAVE
      end
    end
  end
end
