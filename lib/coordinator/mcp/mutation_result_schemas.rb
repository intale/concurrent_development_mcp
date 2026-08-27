# frozen_string_literal: true

module Coordinator
  module Mcp
    module MutationResultSchemas
      module_function

      def for(tool_name)
        contract = Coordinator::Write::Tasks::TargetContractRegistry.fetch(tool_name)
        envelope = Schemas.envelope
        envelope.merge(
          properties: envelope.fetch(:properties).merge(
            data: {
              oneOf: [
                receipt(contract.receipt_class),
                domain_error
              ]
            }
          )
        )
      end

      def receipt(receipt_class)
        names = receipt_class.schema.keys.map { _1.name.to_s }
        {
          type: "object",
          additionalProperties: false,
          properties: names.to_h { [ _1.to_sym, {} ] },
          required: names
        }
      end

      def domain_error
        {
          type: "object",
          additionalProperties: false,
          properties: {
            code: { type: "string", enum: Coordinator::Write::Tasks::DomainErrorV1::ERROR_CODES.map(&:to_s) },
            message: { type: "string" },
            details: { type: "object" }
          },
          required: %w[code message details]
        }
      end
    end
  end
end
