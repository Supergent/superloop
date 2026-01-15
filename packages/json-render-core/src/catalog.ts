import { z } from "zod";
import type {
  ComponentSchema,
  ValidationMode,
  UIElement,
  UITree,
  VisibilityCondition,
} from "./types";
import { VisibilityConditionSchema } from "./visibility";
import { ActionSchema, type ActionDefinition } from "./actions";
import { ValidationConfigSchema, type ValidationFunction } from "./validation";

/**
 * Component definition with visibility and validation support
 */
export interface ComponentDefinition<
  TProps extends ComponentSchema = ComponentSchema,
> {
  /** Zod schema for component props */
  props: TProps;
  /** Whether this component can have children */
  hasChildren?: boolean;
  /** Description for AI generation */
  description?: string;
}

/**
 * Catalog configuration
 */
export interface CatalogConfig<
  TComponents extends Record<string, ComponentDefinition> = Record<
    string,
    ComponentDefinition
  >,
  TActions extends Record<string, ActionDefinition> = Record<
    string,
    ActionDefinition
  >,
  TFunctions extends Record<string, ValidationFunction> = Record<
    string,
    ValidationFunction
  >,
> {
  /** Catalog name */
  name?: string;
  /** Component definitions */
  components: TComponents;
  /** Action definitions with param schemas */
  actions?: TActions;
  /** Custom validation functions */
  functions?: TFunctions;
  /** Validation mode */
  validation?: ValidationMode;
}

/**
 * Catalog instance
 */
export interface Catalog<
  TComponents extends Record<string, ComponentDefinition> = Record<
    string,
    ComponentDefinition
  >,
  TActions extends Record<string, ActionDefinition> = Record<
    string,
    ActionDefinition
  >,
  TFunctions extends Record<string, ValidationFunction> = Record<
    string,
    ValidationFunction
  >,
> {
  /** Catalog name */
  readonly name: string;
  /** Component names */
  readonly componentNames: (keyof TComponents)[];
  /** Action names */
  readonly actionNames: (keyof TActions)[];
  /** Function names */
  readonly functionNames: (keyof TFunctions)[];
  /** Validation mode */
  readonly validation: ValidationMode;
  /** Component definitions */
  readonly components: TComponents;
  /** Action definitions */
  readonly actions: TActions;
  /** Custom validation functions */
  readonly functions: TFunctions;
  /** Full element schema for AI generation */
  readonly elementSchema: z.ZodType<UIElement>;
  /** Full UI tree schema */
  readonly treeSchema: z.ZodType<UITree>;
  /** Check if component exists */
  hasComponent(type: string): boolean;
  /** Check if action exists */
  hasAction(name: string): boolean;
  /** Check if function exists */
  hasFunction(name: string): boolean;
  /** Validate an element */
  validateElement(element: unknown): {
    success: boolean;
    data?: UIElement;
    error?: z.ZodError;
  };
  /** Validate a UI tree */
  validateTree(tree: unknown): {
    success: boolean;
    data?: UITree;
    error?: z.ZodError;
  };
}

/**
 * Create a v2 catalog with visibility, actions, and validation support
 */
export function createCatalog<
  TComponents extends Record<string, ComponentDefinition>,
  TActions extends Record<string, ActionDefinition> = Record<
    string,
    ActionDefinition
  >,
  TFunctions extends Record<string, ValidationFunction> = Record<
    string,
    ValidationFunction
  >,
>(
  config: CatalogConfig<TComponents, TActions, TFunctions>,
): Catalog<TComponents, TActions, TFunctions> {
  const {
    name = "unnamed",
    components,
    actions = {} as TActions,
    functions = {} as TFunctions,
    validation = "strict",
  } = config;

  const componentNames = Object.keys(components) as (keyof TComponents)[];
  const actionNames = Object.keys(actions) as (keyof TActions)[];
  const functionNames = Object.keys(functions) as (keyof TFunctions)[];

  // Create element schema for each component type
  const componentSchemas = componentNames.map((componentName) => {
    const def = components[componentName]!;

    return z.object({
      key: z.string(),
      type: z.literal(componentName as string),
      props: def.props,
      children: z.array(z.string()).optional(),
      parentKey: z.string().nullable().optional(),
      visible: VisibilityConditionSchema.optional(),
    });
  });

  // Create union schema for all components
  let elementSchema: z.ZodType<UIElement>;

  if (componentSchemas.length === 0) {
    elementSchema = z.object({
      key: z.string(),
      type: z.string(),
      props: z.record(z.string(), z.unknown()),
      children: z.array(z.string()).optional(),
      parentKey: z.string().nullable().optional(),
      visible: VisibilityConditionSchema.optional(),
    }) as unknown as z.ZodType<UIElement>;
  } else if (componentSchemas.length === 1) {
    elementSchema = componentSchemas[0] as unknown as z.ZodType<UIElement>;
  } else {
    elementSchema = z.discriminatedUnion("type", [
      componentSchemas[0] as z.ZodObject<any>,
      componentSchemas[1] as z.ZodObject<any>,
      ...(componentSchemas.slice(2) as z.ZodObject<any>[]),
    ]) as unknown as z.ZodType<UIElement>;
  }

  // Create tree schema
  const treeSchema = z.object({
    root: z.string(),
    elements: z.record(z.string(), elementSchema),
  }) as unknown as z.ZodType<UITree>;

  return {
    name,
    componentNames,
    actionNames,
    functionNames,
    validation,
    components,
    actions,
    functions,
    elementSchema,
    treeSchema,

    hasComponent(type: string) {
      return type in components;
    },

    hasAction(name: string) {
      return name in actions;
    },

    hasFunction(name: string) {
      return name in functions;
    },

    validateElement(element: unknown) {
      const result = elementSchema.safeParse(element);
      if (result.success) {
        return { success: true, data: result.data };
      }
      return { success: false, error: result.error };
    },

    validateTree(tree: unknown) {
      const result = treeSchema.safeParse(tree);
      if (result.success) {
        return { success: true, data: result.data };
      }
      return { success: false, error: result.error };
    },
  };
}

/**
 * Generate a prompt for AI that describes the catalog
 */
export function generateCatalogPrompt<
  TComponents extends Record<string, ComponentDefinition>,
  TActions extends Record<string, ActionDefinition>,
  TFunctions extends Record<string, ValidationFunction>,
>(catalog: Catalog<TComponents, TActions, TFunctions>): string {
  const lines: string[] = [
    `# ${catalog.name} Component Catalog`,
    "",
    "## Available Components",
    "",
  ];

  // Components
  for (const name of catalog.componentNames) {
    const def = catalog.components[name]!;
    lines.push(`### ${String(name)}`);
    if (def.description) {
      lines.push(def.description);
    }
    lines.push("");
  }

  // Actions
  if (catalog.actionNames.length > 0) {
    lines.push("## Available Actions");
    lines.push("");
    for (const name of catalog.actionNames) {
      const def = catalog.actions[name]!;
      lines.push(
        `- \`${String(name)}\`${def.description ? `: ${def.description}` : ""}`,
      );
    }
    lines.push("");
  }

  // Visibility
  lines.push("## Visibility Conditions");
  lines.push("");
  lines.push("Components can have a `visible` property:");
  lines.push("- `true` / `false` - Always visible/hidden");
  lines.push('- `{ "path": "/data/path" }` - Visible when path is truthy');
  lines.push('- `{ "auth": "signedIn" }` - Visible when user is signed in');
  lines.push('- `{ "and": [...] }` - All conditions must be true');
  lines.push('- `{ "or": [...] }` - Any condition must be true');
  lines.push('- `{ "not": {...} }` - Negates a condition');
  lines.push('- `{ "eq": [a, b] }` - Equality check');
  lines.push("");

  // Validation
  lines.push("## Validation Functions");
  lines.push("");
  lines.push(
    "Built-in: `required`, `email`, `minLength`, `maxLength`, `pattern`, `min`, `max`, `url`",
  );
  if (catalog.functionNames.length > 0) {
    lines.push(`Custom: ${catalog.functionNames.map(String).join(", ")}`);
  }
  lines.push("");

  return lines.join("\n");
}

/**
 * Type helper to infer component props from catalog
 */
export type InferCatalogComponentProps<
  C extends Catalog<Record<string, ComponentDefinition>>,
> = {
  [K in keyof C["components"]]: z.infer<C["components"][K]["props"]>;
};

/**
 * Options for generating skill prompts
 */
export interface SkillPromptOptions {
  /** Include UITree format explanation */
  includeTreeFormat?: boolean;
  /** Include DynamicValue documentation */
  includeDynamicValues?: boolean;
  /** Include visibility conditions documentation */
  includeVisibility?: boolean;
  /** Include actions documentation */
  includeActions?: boolean;
  /** Include example UITree */
  includeExample?: boolean;
  /** Custom context paths to document */
  contextPaths?: { path: string; description: string }[];
}

/**
 * Generate a comprehensive skill prompt for AI that documents how to generate UITrees
 *
 * This generates markdown documentation suitable for embedding in Claude Code skills
 * or other AI prompts that need to teach an LLM how to generate valid UITrees.
 */
export function generateSkillPrompt<
  TComponents extends Record<string, ComponentDefinition>,
  TActions extends Record<string, ActionDefinition>,
  TFunctions extends Record<string, ValidationFunction>,
>(
  catalog: Catalog<TComponents, TActions, TFunctions>,
  options: SkillPromptOptions = {},
): string {
  const {
    includeTreeFormat = true,
    includeDynamicValues = true,
    includeVisibility = true,
    includeActions = true,
    includeExample = true,
    contextPaths = [],
  } = options;

  const lines: string[] = [];

  // Header
  lines.push(`# ${catalog.name} UITree Generation Guide`);
  lines.push("");

  // UITree Format
  if (includeTreeFormat) {
    lines.push("## UITree Format");
    lines.push("");
    lines.push("A UITree is a flat structure with a root element and a map of elements:");
    lines.push("");
    lines.push("```json");
    lines.push("{");
    lines.push('  "root": "main",');
    lines.push('  "elements": {');
    lines.push('    "main": {');
    lines.push('      "type": "ComponentType",');
    lines.push('      "props": { ... },');
    lines.push('      "children": ["child1", "child2"]');
    lines.push("    },");
    lines.push('    "child1": { "type": "...", "props": { ... } },');
    lines.push('    "child2": { "type": "...", "props": { ... } }');
    lines.push("  }");
    lines.push("}");
    lines.push("```");
    lines.push("");
    lines.push("**Key rules**:");
    lines.push("- `root` points to the top-level element key");
    lines.push("- `elements` is a flat map (no nesting)");
    lines.push("- `children` array contains element keys (strings), not objects");
    lines.push("- Every element has `type` (component name) and `props` (properties)");
    lines.push("");
  }

  // DynamicValue
  if (includeDynamicValues) {
    lines.push("## Data Binding with DynamicValue");
    lines.push("");
    lines.push('Use `{ "path": "/some/path" }` to bind data at runtime:');
    lines.push("");
    lines.push("```json");
    lines.push("{");
    lines.push('  "type": "Text",');
    lines.push('  "props": {');
    lines.push('    "children": { "path": "/user/name" }');
    lines.push("  }");
    lines.push("}");
    lines.push("```");
    lines.push("");
    lines.push("The path references data in the context object using JSON Pointer syntax.");
    lines.push("");

    if (contextPaths.length > 0) {
      lines.push("### Available Context Paths");
      lines.push("");
      lines.push("| Path | Description |");
      lines.push("|------|-------------|");
      for (const { path, description } of contextPaths) {
        lines.push(`| \`${path}\` | ${description} |`);
      }
      lines.push("");
    }
  }

  // Visibility
  if (includeVisibility) {
    lines.push("## Visibility Conditions");
    lines.push("");
    lines.push("Control when elements render with `visibility`:");
    lines.push("");
    lines.push("```json");
    lines.push("{");
    lines.push('  "type": "Alert",');
    lines.push('  "props": { "children": "Error!" },');
    lines.push('  "visibility": {');
    lines.push('    "conditions": [');
    lines.push('      { "path": "/hasError", "op": "eq", "value": true }');
    lines.push("    ],");
    lines.push('    "logic": "and"');
    lines.push("  }");
    lines.push("}");
    lines.push("```");
    lines.push("");
    lines.push("**Operators**: `eq`, `neq`, `gt`, `gte`, `lt`, `lte`");
    lines.push("");
    lines.push("**Logic**: `and` (all must match), `or` (any must match)");
    lines.push("");
    lines.push("**Shortcuts**:");
    lines.push("- `true` / `false` - Always visible/hidden");
    lines.push('- `{ "path": "/data/path" }` - Visible when path is truthy');
    lines.push('- `{ "auth": "signedIn" }` - Visible when user is signed in');
    lines.push("");
  }

  // Components
  lines.push("## Available Components");
  lines.push("");

  for (const name of catalog.componentNames) {
    const def = catalog.components[name]!;
    lines.push(`### ${String(name)}`);
    lines.push("");

    if (def.description) {
      lines.push(def.description);
      lines.push("");
    }

    // Extract props from Zod schema
    const propsDoc = extractZodSchemaDoc(def.props);
    if (propsDoc.length > 0) {
      lines.push("**Props:**");
      lines.push("");
      lines.push("| Prop | Type | Required | Description |");
      lines.push("|------|------|----------|-------------|");
      for (const prop of propsDoc) {
        const reqMark = prop.required ? "Yes" : "No";
        lines.push(`| \`${prop.name}\` | ${prop.type} | ${reqMark} | ${prop.description} |`);
      }
      lines.push("");
    }

    if (def.hasChildren) {
      lines.push("*This component can have children.*");
      lines.push("");
    }
  }

  // Actions
  if (includeActions && catalog.actionNames.length > 0) {
    lines.push("## Available Actions");
    lines.push("");
    lines.push("Actions can be triggered by interactive components:");
    lines.push("");
    lines.push("```json");
    lines.push("{");
    lines.push('  "type": "Button",');
    lines.push('  "props": {');
    lines.push('    "children": "Submit",');
    lines.push('    "action": "submit_form"');
    lines.push("  }");
    lines.push("}");
    lines.push("```");
    lines.push("");
    lines.push("| Action | Description |");
    lines.push("|--------|-------------|");
    for (const name of catalog.actionNames) {
      const def = catalog.actions[name]!;
      lines.push(`| \`${String(name)}\` | ${def.description ?? "No description"} |`);
    }
    lines.push("");
  }

  // Example
  if (includeExample) {
    lines.push("## Example UITree");
    lines.push("");
    lines.push("```json");

    // Generate a simple example based on available components
    const example = generateExampleTree(catalog.componentNames, catalog.components);
    lines.push(JSON.stringify(example, null, 2));

    lines.push("```");
    lines.push("");
  }

  return lines.join("\n");
}

/**
 * Extract documentation from a Zod schema
 */
interface PropDoc {
  name: string;
  type: string;
  required: boolean;
  description: string;
}

function extractZodSchemaDoc(schema: unknown): PropDoc[] {
  const props: PropDoc[] = [];

  // Handle ZodObject - use duck typing for Zod 4 compatibility
  if (schema && typeof schema === "object" && "shape" in schema) {
    const shape = (schema as { shape: Record<string, unknown> }).shape;
    for (const [key, value] of Object.entries(shape)) {
      props.push({
        name: key,
        type: getZodTypeName(value),
        required: !isZodOptional(value),
        description: getZodDescription(value),
      });
    }
  }

  return props;
}

function getZodTypeName(schema: unknown): string {
  if (!schema || typeof schema !== "object") return "unknown";

  // Unwrap optional/nullable using duck typing
  let inner = schema;
  while (inner && typeof inner === "object") {
    const def = (inner as { _def?: { innerType?: unknown } })._def;
    if (def?.innerType && isOptionalType(inner)) {
      inner = def.innerType;
    } else {
      break;
    }
  }

  // Use constructor name for type detection (works with Zod 4)
  const typeName = inner?.constructor?.name ?? "";

  if (typeName.includes("String")) return "string";
  if (typeName.includes("Number")) return "number";
  if (typeName.includes("Boolean")) return "boolean";

  if (typeName.includes("Array")) {
    const def = (inner as { _def?: { element?: unknown } })._def;
    if (def?.element) {
      const elementType = getZodTypeName(def.element);
      return `${elementType}[]`;
    }
    return "array";
  }

  if (typeName.includes("Enum")) {
    const def = (inner as { _def?: { entries?: Record<string, string> } })._def;
    if (def?.entries) {
      const values = Object.values(def.entries);
      if (values.length <= 4) {
        return values.map((v) => `"${v}"`).join(" | ");
      }
    }
    return "enum";
  }

  if (typeName.includes("Literal")) {
    const def = (inner as { _def?: { values?: Set<unknown> } })._def;
    if (def?.values) {
      const value = [...def.values][0];
      return typeof value === "string" ? `"${value}"` : String(value);
    }
    return "literal";
  }

  if (typeName.includes("Union")) {
    const def = (inner as { _def?: { options?: unknown[] } })._def;
    if (def?.options) {
      // Check for DynamicValue pattern
      const hasDynamicPath = def.options.some((opt) => {
        if (opt && typeof opt === "object" && "shape" in opt) {
          const shape = (opt as { shape: Record<string, unknown> }).shape;
          return "path" in shape;
        }
        return false;
      });
      if (hasDynamicPath) {
        const literalTypes = def.options
          .filter((opt) => !(opt && typeof opt === "object" && "shape" in opt))
          .map((opt) => getZodTypeName(opt));
        if (literalTypes.length > 0) {
          return `${literalTypes[0]} | DynamicValue`;
        }
        return "DynamicValue";
      }
      return def.options.map((opt) => getZodTypeName(opt)).join(" | ");
    }
    return "union";
  }

  if (typeName.includes("Object")) return "object";
  if (typeName.includes("Record")) return "Record";

  return "unknown";
}

function isOptionalType(schema: unknown): boolean {
  if (!schema || typeof schema !== "object") return false;
  const typeName = schema.constructor?.name ?? "";
  return (
    typeName.includes("Optional") ||
    typeName.includes("Nullable") ||
    typeName.includes("Default")
  );
}

function isZodOptional(schema: unknown): boolean {
  return isOptionalType(schema);
}

function getZodDescription(schema: unknown): string {
  if (!schema || typeof schema !== "object") return "";
  const def = (schema as { _def?: { description?: string } })._def;
  return def?.description ?? "";
}

/**
 * Generate a simple example UITree from catalog
 */
function generateExampleTree(
  componentNames: readonly (string | number | symbol)[],
  components: Record<string, ComponentDefinition>,
): UITree {
  const elements: Record<string, UIElement> = {};

  // Find a container component (has children)
  const containerName = componentNames.find(
    (name) => components[String(name)]?.hasChildren
  );

  // Find a text-like component (no children)
  const textName = componentNames.find(
    (name) => !components[String(name)]?.hasChildren
  );

  if (containerName && textName) {
    elements["main"] = {
      key: "main",
      type: String(containerName),
      props: {},
      children: ["content"],
    };
    elements["content"] = {
      key: "content",
      type: String(textName),
      props: { children: "Hello world" },
    };
  } else if (componentNames.length > 0) {
    const firstName = String(componentNames[0]);
    elements["main"] = {
      key: "main",
      type: firstName,
      props: {},
    };
  } else {
    elements["main"] = {
      key: "main",
      type: "Text",
      props: { children: "No components defined" },
    };
  }

  return { root: "main", elements };
}
