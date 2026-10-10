import { interfaceNotFound } from "./errors.ts";
import { defineInterface, type Interface } from "./interface.ts";

export interface ServerInfo {
  readonly vendor: string;
  readonly product: string;
  readonly version: string;
  readonly url: string;
}

// Part of the protocol itself, so it is written out here rather than generated.
const description = `interface org.varlink.service

method GetInfo() -> (
  vendor: string,
  product: string,
  version: string,
  url: string,
  interfaces: []string
)

method GetInterfaceDescription(interface: string) -> (description: string)

error InterfaceNotFound (interface: string)
error MethodNotFound (method: string)
error MethodNotImplemented (method: string)
error InvalidParameter (parameter: string)
error PermissionDenied ()
error ExpectedMore ()
`;

export function serviceInterface(
  info: ServerInfo,
  interfaces: () => Iterable<Interface>,
): Interface {
  return defineInterface(description, {
    GetInfo: () => ({
      ...info,
      interfaces: Array.from(interfaces(), (entry) => entry.schema.name),
    }),
    GetInterfaceDescription: ({
      interface: name,
    }: {
      readonly interface: string;
    }) => {
      for (const entry of interfaces()) {
        if (entry.schema.name === name)
          return { description: entry.description };
      }
      throw interfaceNotFound(name);
    },
  });
}
