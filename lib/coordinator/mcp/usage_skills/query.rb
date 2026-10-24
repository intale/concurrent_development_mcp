# frozen_string_literal: true

module Coordinator::Mcp::UsageSkills
  # Server documentation is static transport content, not a projection or fallback.
  class Query
    def list(input)
      validated = ListContract.new.call(input)
      return invalid(validated.errors.to_h) if validated.failure?

      definitions = Catalog.all.sort_by(&:name)
      definitions = definitions.select { _1.name == validated[:name] } if validated[:name]
      definitions = definitions.select { _1.name > validated[:after_skill_id] } if validated[:after_skill_id]
      limit = validated[:limit] || 20
      selected = definitions.take(limit)
      has_more = definitions.length > selected.length
      result(
        status: "ok", summary: "Built-in server capability Skills; static application content, independent of databases.",
        data: PageData.new(page: Page.new(
          items: selected.map { summary(_1) }, has_more:,
          next_skill_id: has_more ? selected.last.name : nil
        ))
      )
    end

    def get(input)
      validated = GetContract.new.call(input)
      return invalid(validated.errors.to_h) if validated.failure?

      definition = Catalog.all.find { _1.name == validated[:name] }
      if definition && (!validated[:revision] || validated[:revision] == Catalog::RELEASE)
        document = Document.new(summary(definition).to_h.merge(instructions: definition.instructions, assets: []))
        return result(status: "ok", summary: "Built-in server usage Skill from the running application.", data: DocumentData.new(skill: document))
      end

      not_found("server_skill_not_found", "No built-in server Skill matches this name and bundle revision.", validated.to_h)
    end

    def asset(input)
      validated = AssetContract.new.call(input)
      return invalid(validated.errors.to_h) if validated.failure?

      not_found("server_skill_asset_not_found", "Built-in usage Skills are self-contained and have no support assets.", validated.to_h)
    end

    private

    def summary(definition)
      Summary.new(
        source: "server", skill_id: definition.name, name: definition.name, scope: Catalog::SCOPE,
        revision: Catalog::RELEASE, description: definition.description, tools: definition.tools
      )
    end

    def invalid(details)
      result(status: "invalid", summary: "Built-in Skill input is invalid.", data: Coordinator::Mcp::ResultV1::DomainError.new(
        code: "invalid_input", message: "Built-in Skill input is invalid", details:
      ))
    end

    def not_found(code, message, details)
      result(status: "not_found", summary: message, data: Coordinator::Mcp::ResultV1::DomainError.new(code:, message:, details:))
    end

    def result(status:, summary:, data:)
      Coordinator::Mcp::ResultV1.new(
        status:, summary:, data:, command_id: nil, receipt: nil, context_token: nil, warnings: [], next_actions: []
      )
    end
  end
end
