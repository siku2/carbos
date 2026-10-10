import type { Schema, StructType, Type } from "./idl.ts";
import { isRecord } from "./protocol.ts";

/** Returns the first field that does not match, if any. */
export function invalidField(
  schema: Schema,
  struct: StructType,
  value: Record<string, unknown>,
): string | undefined {
  const known = new Set<string>();
  for (const field of struct.fields) {
    known.add(field.name);
    if (!matches(schema, field.type, value[field.name])) return field.name;
  }
  return Object.keys(value).find((key) => !known.has(key));
}

function matches(schema: Schema, type: Type, value: unknown): boolean {
  if (value === undefined || value === null) return type.kind === "nullable";
  switch (type.kind) {
    case "bool":
      return typeof value === "boolean";
    case "int":
      return Number.isInteger(value);
    case "float":
      return typeof value === "number" && Number.isFinite(value);
    case "string":
      return typeof value === "string";
    case "object":
      return isRecord(value);
    case "nullable":
      return matches(schema, type.element, value);
    case "array":
      return (
        Array.isArray(value) &&
        value.every((item) => matches(schema, type.element, item))
      );
    case "map":
      return (
        isRecord(value) &&
        Object.values(value).every((item) =>
          matches(schema, type.element, item),
        )
      );
    case "enum":
      return typeof value === "string" && type.values.includes(value);
    case "struct":
      return isRecord(value) && invalidField(schema, type, value) === undefined;
    case "named": {
      const definition = schema.types.get(type.name);
      return (
        definition !== undefined && matches(schema, definition.type, value)
      );
    }
  }
}
