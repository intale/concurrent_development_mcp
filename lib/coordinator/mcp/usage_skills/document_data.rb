# frozen_string_literal: true

module Coordinator::Mcp::UsageSkills
  class DocumentData < Coordinator::Shared::Value
    attribute :skill, Document
  end
end
