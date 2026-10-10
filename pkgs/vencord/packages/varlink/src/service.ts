import { interfaceNotFound } from "./errors.ts";
import { call, defineInterface, type Interface, string } from "./interface.ts";

export interface ServerInfo {
  readonly vendor: string;
  readonly product: string;
  readonly version: string;
  readonly url: string;
}

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
    GetInfo: call(
      () => undefined,
      () => ({
        ...info,
        interfaces: Array.from(interfaces(), (entry) => entry.name),
      }),
    ),
    GetInterfaceDescription: call(
      (parameters) => string(parameters, "interface"),
      (name) => {
        for (const entry of interfaces()) {
          if (entry.name === name) return { description: entry.description };
        }
        throw interfaceNotFound(name);
      },
    ),
  });
}
