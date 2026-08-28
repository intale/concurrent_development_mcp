# frozen_string_literal: true

module Coordinator
  module Mcp
    module MutationResultSchemas
      module_function

      def for(tool_name)
        contract = Coordinator::Write::Tasks::TargetContractRegistry.fetch(tool_name)
        Schemas.envelope(
          data: {
            oneOf: [
              receipt(contract.receipt_class),
              domain_error
            ]
          },
          next_action: NextActionSchemas.schema
        )
      end

      def receipt(receipt_class)
        DryStructSchema.new.call(receipt_class)
      end

      def domain_error
        {
          title: "Coordinator::Write::Tasks::DomainErrorV1",
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
