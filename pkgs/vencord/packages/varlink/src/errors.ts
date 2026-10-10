export class VarlinkError extends Error {
  readonly error: string;
  readonly parameters: Record<string, unknown>;

  constructor(error: string, parameters: Record<string, unknown> = {}) {
    super(error);
    this.name = "VarlinkError";
    this.error = error;
    this.parameters = parameters;
  }
}

export const interfaceNotFound = (name: string) =>
  new VarlinkError("org.varlink.service.InterfaceNotFound", {
    interface: name,
  });

export const methodNotFound = (method: string) =>
  new VarlinkError("org.varlink.service.MethodNotFound", { method });

export const invalidParameter = (parameter: string) =>
  new VarlinkError("org.varlink.service.InvalidParameter", { parameter });
