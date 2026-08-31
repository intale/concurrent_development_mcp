declare module "@adminlte/react/css";

declare module "react_ujs" {
  import type { ComponentType } from "react";

  type ReactRailsComponent = ComponentType<Record<string, never>>;
  type SearchScope = string | ParentNode;

  interface ReactRailsUJSDriver {
    detectEvents(): void;
    getConstructor: (className: string) => ReactRailsComponent | undefined;
    mountComponents(searchScope?: SearchScope): void;
    unmountComponents(searchScope?: SearchScope): void;
  }

  const ReactRailsUJS: ReactRailsUJSDriver;
  export default ReactRailsUJS;
}
