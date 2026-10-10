export type Type =
  | { readonly kind: "bool" | "int" | "float" | "string" | "object" }
  | { readonly kind: "nullable" | "array" | "map"; readonly element: Type }
  | { readonly kind: "enum"; readonly values: readonly string[] }
  | StructType
  | { readonly kind: "named"; readonly name: string };

export interface StructType {
  readonly kind: "struct";
  readonly fields: readonly Field[];
}

export interface Field {
  readonly name: string;
  readonly type: Type;
  readonly doc: string;
}

export interface TypeDefinition {
  readonly name: string;
  readonly type: Type;
  readonly doc: string;
}

export interface MethodDefinition {
  readonly name: string;
  readonly input: StructType;
  readonly output: StructType;
  readonly doc: string;
}

export interface ErrorDefinition {
  readonly name: string;
  readonly parameters: StructType;
  readonly doc: string;
}

export interface Schema {
  readonly name: string;
  readonly doc: string;
  readonly types: ReadonlyMap<string, TypeDefinition>;
  readonly methods: ReadonlyMap<string, MethodDefinition>;
  readonly errors: ReadonlyMap<string, ErrorDefinition>;
}

export class IdlError extends Error {
  override readonly name = "IdlError";
}

interface Token {
  readonly text: string;
  readonly offset: number;
  /** The comment lines right above the token. */
  readonly doc: string;
}

const interfaceName =
  /^[A-Za-z]([-]*[A-Za-z0-9])*(\.[A-Za-z0-9]([-]*[A-Za-z0-9])*)+$/;
const memberName = /^[A-Z][A-Za-z0-9]*$/;
const fieldName = /^[A-Za-z](_?[A-Za-z0-9])*$/;
const builtins = new Set(["bool", "int", "float", "string", "object"]);

function tokenize(source: string): Token[] {
  const pattern =
    /(\s+)|#([^\n]*)|(->|\[\]|\[string\]|[?():,]|[A-Za-z][\w.-]*)/y;
  const tokens: Token[] = [];
  let doc: string[] = [];
  while (pattern.lastIndex < source.length) {
    const offset = pattern.lastIndex;
    const match = pattern.exec(source);
    if (match === null) {
      throw new IdlError(`${position(source, offset)}: unexpected character`);
    }
    const [, space, comment, text] = match;
    if (space !== undefined) {
      if (space.split("\n").length > 2) doc = [];
    } else if (comment !== undefined) {
      doc.push(comment.replace(/^ /, ""));
    } else if (text !== undefined) {
      tokens.push({ text, offset, doc: doc.join("\n") });
      doc = [];
    }
  }
  return tokens;
}

function position(source: string, offset: number): string {
  const before = source.slice(0, offset).split("\n");
  return `${before.length}:${(before.at(-1)?.length ?? 0) + 1}`;
}

export function parse(source: string): Schema {
  const tokens = tokenize(source);
  let index = 0;

  const fail = (message: string, token = tokens[index]): never => {
    const where =
      token === undefined ? "end of input" : position(source, token.offset);
    throw new IdlError(`${where}: ${message}`);
  };
  const next = (): Token => tokens[index++] ?? fail("unexpected end of input");
  const accept = (text: string): boolean => {
    if (tokens[index]?.text !== text) return false;
    index++;
    return true;
  };
  const expect = (text: string): Token => {
    const token = next();
    if (token.text !== text)
      fail(`expected "${text}", found "${token.text}"`, token);
    return token;
  };
  const name = (pattern: RegExp, what: string): string => {
    const token = next();
    if (!pattern.test(token.text))
      fail(`invalid ${what} "${token.text}"`, token);
    return token.text;
  };

  const parseType = (): Type => {
    if (accept("?")) return { kind: "nullable", element: parseNonNullable() };
    return parseNonNullable();
  };

  const parseNonNullable = (): Type => {
    const token = tokens[index];
    if (accept("[]")) return { kind: "array", element: parseType() };
    if (accept("[string]")) return { kind: "map", element: parseType() };
    if (token?.text === "(") return parseStructOrEnum();
    const text = next().text;
    if (builtins.has(text)) return { kind: text } as Type;
    if (!memberName.test(text)) fail(`invalid type "${text}"`, token);
    return { kind: "named", name: text };
  };

  const parseStructOrEnum = (): StructType | Type => {
    expect("(");
    if (accept(")")) return { kind: "struct", fields: [] };
    if (tokens[index + 1]?.text !== ":") {
      const values: string[] = [];
      do values.push(name(fieldName, "enum value"));
      while (accept(","));
      expect(")");
      return { kind: "enum", values };
    }
    const fields: Field[] = [];
    do {
      const { doc } = tokens[index] ?? fail("unexpected end of input");
      const field = name(fieldName, "field name");
      expect(":");
      fields.push({ name: field, type: parseType(), doc });
    } while (accept(","));
    expect(")");
    return { kind: "struct", fields };
  };

  const parseStruct = (): StructType => {
    const start = tokens[index];
    const type = parseStructOrEnum();
    if (type.kind !== "struct") fail("expected a struct", start);
    return type as StructType;
  };

  const head = expect("interface");
  const schema = {
    name: name(interfaceName, "interface name"),
    doc: head.doc,
    types: new Map<string, TypeDefinition>(),
    methods: new Map<string, MethodDefinition>(),
    errors: new Map<string, ErrorDefinition>(),
  };
  const members = new Set<string>();

  while (index < tokens.length) {
    const keyword = next();
    const memberToken = tokens[index];
    const member = name(memberName, "member name");
    if (members.has(member)) fail(`"${member}" is defined twice`, memberToken);
    members.add(member);
    const { doc } = keyword;

    switch (keyword.text) {
      case "type": {
        const type = parseStructOrEnum();
        schema.types.set(member, { name: member, type, doc });
        break;
      }
      case "method": {
        const input = parseStruct();
        expect("->");
        schema.methods.set(member, {
          name: member,
          input,
          output: parseStruct(),
          doc,
        });
        break;
      }
      case "error":
        schema.errors.set(member, {
          name: member,
          parameters: parseStruct(),
          doc,
        });
        break;
      default:
        fail(
          `expected "type", "method" or "error", found "${keyword.text}"`,
          keyword,
        );
    }
  }

  checkReferences(schema);
  return schema;
}

function checkReferences(schema: Schema): void {
  const visit = (type: Type, where: string): void => {
    switch (type.kind) {
      case "named":
        if (!schema.types.has(type.name)) {
          throw new IdlError(`${where}: unknown type "${type.name}"`);
        }
        break;
      case "nullable":
      case "array":
      case "map":
        visit(type.element, where);
        break;
      case "struct":
        for (const field of type.fields)
          visit(field.type, `${where}.${field.name}`);
        break;
    }
  };
  for (const { name, type } of schema.types.values()) visit(type, name);
  for (const { name, input, output } of schema.methods.values()) {
    visit(input, name);
    visit(output, name);
  }
  for (const { name, parameters } of schema.errors.values())
    visit(parameters, name);
}
