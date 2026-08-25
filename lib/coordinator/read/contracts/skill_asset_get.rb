# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class SkillAssetGet < SkillGet
      params do
        required(:name).filled(:string)
        required(:scope).filled(:string)
        required(:path).filled(:string)
      end

      rule(:path) do
        valid = value.encoding == Encoding::UTF_8 && value.valid_encoding? &&
                value.bytesize.between?(1, Types::SKILL_ASSET_PATH_MAXIMUM_BYTES) &&
                !value.start_with?("/") && !value.include?("\\") &&
                !/[\u0000-\u001f\u007f]/.match?(value) &&
                value.split("/", -1).none? { _1.empty? || _1 == "." || _1 == ".." }
        key.failure("must be a safe relative POSIX path") unless valid
      end
    end
  end
end
