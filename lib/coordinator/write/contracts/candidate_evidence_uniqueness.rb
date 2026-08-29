# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateEvidenceUniqueness < Dry::Validation::Contract
      params do
        required(:manifest_files).array(:hash) do
          required(:status).filled(:string)
          optional(:old_path).maybe(:string)
          optional(:new_path).maybe(:string)
          optional(:old_blob_oid).maybe(:string)
          optional(:new_blob_oid).maybe(:string)
          optional(:old_mode).maybe(:string)
          optional(:new_mode).maybe(:string)
        end
        required(:actual_resource_evidence).array(:hash) do
          required(:path).filled(:string)
          optional(:base_blob_oid).maybe(:string)
        end
        required(:build_input_keys).array(:string)
        required(:environment_names).array(:string)
      end

      rule(:manifest_files) do
        key.failure("contains duplicate normalized entries") unless value.uniq.length == value.length
        value.each_with_index do |file, index|
          same_path = file[:old_path] == file[:new_path]
          valid = case file.fetch(:status)
          when "modified", "type_changed", "submodule_changed"
            same_path
          when "renamed", "copied"
            !same_path
          else
            true
          end
          key([ :manifest_files, index ]).failure("has invalid normalized path semantics") unless valid
        end
      end

      rule(:actual_resource_evidence) do
        key.failure("must contain between 1 and 32 resources") unless (1..32).cover?(value.map { _1[:path] }.uniq.length)
        conflicting = value.group_by { _1[:path] }.values.any? do |entries|
          entries.map { _1[:base_blob_oid] }.uniq.length > 1
        end
        key.failure("contains conflicting base evidence for one normalized resource") if conflicting
      end

      rule(:build_input_keys) do
        key.failure("contains duplicate normalized inputs") unless value.uniq.length == value.length
      end

      rule(:environment_names) do
        key.failure("contains duplicate environment names") unless value.uniq.length == value.length
      end
    end
  end
end
