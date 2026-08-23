# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class SubmitCandidate < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: [ "agent" ])
          required(:id).filled(:string)
        end
        required(:candidate_id).filled(:string)
        required(:change_set_id).filled(:string)
        required(:work_item_id).filled(:string)
        required(:attempt_id).filled(:string)
        required(:repository_id).filled(:string)
        required(:target_branch).filled(:string)
        required(:base_commit_oid).filled(:string)
        required(:head_commit_oid).filled(:string)
        required(:checkpoint_kind).filled(:string, included_in?: Types::CANDIDATE_CHECKPOINT_KINDS)
        required(:lease_set_id).filled(:string)
        required(:leases).array(:hash) do
          required(:resource_key_hash).filled(:string)
          required(:lease_id).filled(:string)
          required(:fencing_token).filled(:integer)
        end
        required(:change_manifest).hash do
          required(:collector_version).filled(:string)
          required(:files).array(:hash) do
            required(:status).filled(:string, included_in?: Types::CANDIDATE_MANIFEST_STATUSES)
            optional(:old_path).maybe(:string)
            optional(:new_path).maybe(:string)
            optional(:old_blob_oid).maybe(:string)
            optional(:new_blob_oid).maybe(:string)
            optional(:old_mode).maybe(:string, included_in?: Types::CANDIDATE_GIT_FILE_MODES)
            optional(:new_mode).maybe(:string, included_in?: Types::CANDIDATE_GIT_FILE_MODES)
          end
        end
        optional(:build_context).hash do
          required(:collector_version).filled(:string)
          required(:inputs).array(:hash) do
            required(:kind).filled(:string, included_in?: Types::CANDIDATE_BUILD_INPUT_KINDS)
            required(:path).filled(:string)
            required(:blob_oid).filled(:string)
          end
          required(:environment).array(:hash) do
            required(:name).filled(:string)
            required(:value).filled(:string)
          end
          optional(:dependency_graph_digest).maybe(:string)
          optional(:test_environment_digest).maybe(:string)
        end
      end

      rule(:command_id, :candidate_id, :change_set_id, :work_item_id, :attempt_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:id))
      end

      rule(:repository_id) do
        key.failure("must be a valid repository identifier") unless Types::REPOSITORY_ID_PATTERN.match?(value)
      end

      rule(:target_branch) do
        key.failure("must be a canonical Git branch ref") unless valid_branch?(value)
      end

      rule(:base_commit_oid, :head_commit_oid) do
        base = values[:base_commit_oid]
        head = values[:head_commit_oid]
        next unless base && head

        key(:base_commit_oid).failure("must be a lowercase SHA-1 or SHA-256 OID") unless Types::GIT_OID_PATTERN.match?(base)
        key(:head_commit_oid).failure("must be a lowercase SHA-1 or SHA-256 OID") unless Types::GIT_OID_PATTERN.match?(head)
        key(:head_commit_oid).failure("must use the base repository object format") if base.length != head.length
        key(:head_commit_oid).failure("must differ from base_commit_oid") if base == head
      end

      rule(:lease_set_id) do
        key.failure("must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:leases) do
        key.failure("must contain between 1 and 32 entries") unless (1..32).cover?(value.length)
        keys = value.map { [ _1[:resource_key_hash], _1[:lease_id], _1[:fencing_token] ] }
        key.failure("must not contain duplicate lease observations") unless keys.uniq.length == keys.length
        hashes = value.map { _1[:resource_key_hash] }
        key.failure("must not contain duplicate resource identities") unless hashes.uniq.length == hashes.length

        value.each_with_index do |lease, index|
          key([ :leases, index, :resource_key_hash ]).failure("must be a SHA-256 digest") unless Types::SHA256_DIGEST_PATTERN.match?(lease[:resource_key_hash])
          key([ :leases, index, :lease_id ]).failure("must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(lease[:lease_id])
          key([ :leases, index, :fencing_token ]).failure("must be positive") unless lease[:fencing_token].positive?
        end
      end

      rule(:change_manifest) do
        files = value.fetch(:files)
        key([ :change_manifest, :files ]).failure("must contain between 1 and 256 entries") unless (1..256).cover?(files.length)
        unless valid_collector_version?(value.fetch(:collector_version))
          key([ :change_manifest, :collector_version ]).failure("must contain 1 to 100 characters")
        end
        files.each_with_index do |file, index|
          key([ :change_manifest, :files, index ]).failure("does not match its status field contract") unless valid_manifest_file?(file)
        end
      end

      rule(:base_commit_oid, :head_commit_oid, :change_manifest) do
        base = values[:base_commit_oid]
        next unless base && Types::GIT_OID_PATTERN.match?(base)

        candidate_oids = [ values[:head_commit_oid] ]
        candidate_oids.concat(values[:change_manifest].fetch(:files).flat_map { [ _1[:old_blob_oid], _1[:new_blob_oid] ] })
        context = values[:build_context]
        candidate_oids.concat(context.fetch(:inputs).map { _1[:blob_oid] }) if context
        candidate_oids.compact.each do |oid|
          next if Types::GIT_OID_PATTERN.match?(oid) && oid.length == base.length

          key.failure("all submitted Git OIDs must use the base repository object format")
          break
        end
      end

      rule(:build_context) do
        next unless value

        inputs = value.fetch(:inputs)
        environment = value.fetch(:environment)
        key([ :build_context, :inputs ]).failure("must contain at most 64 entries") if inputs.length > 64
        key([ :build_context, :environment ]).failure("must contain at most 32 entries") if environment.length > 32
        key.failure("must contain at least one input or environment entry") if inputs.empty? && environment.empty?
        unless valid_collector_version?(value.fetch(:collector_version))
          key([ :build_context, :collector_version ]).failure("must contain 1 to 100 characters")
        end

        environment.each_with_index do |entry, index|
          name = entry.fetch(:name)
          content = entry.fetch(:value)
          key([ :build_context, :environment, index, :name ]).failure("must contain 1 to 100 characters") unless (1..100).cover?(name.length)
          key([ :build_context, :environment, index, :value ]).failure("must contain 1 to 500 characters") unless (1..500).cover?(content.length)
        end
        %i[dependency_graph_digest test_environment_digest].each do |name|
          digest = value[name]
          next if digest.nil? || Types::SHA256_DIGEST_PATTERN.match?(digest)

          key([ :build_context, name ]).failure("must be a SHA-256 digest")
        end
      end

      private

      def valid_branch?(value)
        value.valid_encoding? && value.encoding == Encoding::UTF_8 &&
          value.bytesize.between?(1, 255) &&
          !/[\u0000-\u0020\u007f~^:?*\[\\]/.match?(value) &&
          !value.include?("..") && !value.include?("@{") &&
          !value.start_with?("/", ".") && !value.end_with?("/", ".") &&
          value.split("/", -1).none? { _1.empty? || _1.end_with?(".lock") }
      end

      def valid_collector_version?(value)
        (1..100).cover?(value.length)
      end

      def valid_manifest_file?(file)
        status = file.fetch(:status)
        old_side = [ file[:old_path], file[:old_blob_oid], file[:old_mode] ]
        new_side = [ file[:new_path], file[:new_blob_oid], file[:new_mode] ]
        valid = case status
        when "added"
          old_side.all?(&:nil?) && new_side.none?(&:nil?)
        when "deleted"
          old_side.none?(&:nil?) && new_side.all?(&:nil?)
        when "modified"
          complete_sides?(old_side, new_side) &&
            file[:old_mode] == file[:new_mode] && file[:old_blob_oid] != file[:new_blob_oid]
        when "renamed", "copied"
          complete_sides?(old_side, new_side)
        when "type_changed"
          complete_sides?(old_side, new_side) && file[:old_mode] != file[:new_mode]
        when "submodule_changed"
          complete_sides?(old_side, new_side) &&
            file[:old_mode] == "160000" && file[:new_mode] == "160000" &&
            file[:old_blob_oid] != file[:new_blob_oid]
        else
          false
        end
        valid
      end

      def complete_sides?(old_side, new_side)
        old_side.none?(&:nil?) && new_side.none?(&:nil?)
      end
    end
  end
end
