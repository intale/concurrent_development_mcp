import type { CodegenConfig } from "@graphql-codegen/cli";

const config: CodegenConfig = {
  schema: "../app/graphql/schema.graphql",
  documents: ["src/**/*.graphql"],
  generates: {
    "src/gql/": {
      preset: "client",
      presetConfig: {
        fragmentMasking: false
      },
      config: {
        defaultScalarType: "unknown",
        immutableTypes: true,
        strictScalars: true,
        useTypeImports: true
      }
    }
  }
};

export default config;
