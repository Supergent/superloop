import { describe, it, expect } from 'vitest';
import ts from 'typescript';
import { parseSchema } from '../schema-parser.js';

describe('schema-parser', () => {
  describe('parseSchema', () => {
    it('should extract table names from schema', () => {
      const code = `
        import { defineSchema, defineTable } from 'convex/server';
        import { v } from 'convex/values';

        export default defineSchema({
          users: defineTable({
            name: v.string(),
            email: v.string(),
          }),
          posts: defineTable({
            title: v.string(),
            content: v.string(),
          }),
        });
      `;

      const sourceFile = ts.createSourceFile(
        'schema.ts',
        code,
        ts.ScriptTarget.ES2022,
        true
      );

      const schema = parseSchema(sourceFile);

      expect(schema.tables).toHaveLength(2);
      expect(schema.tables[0]?.name).toBe('users');
      expect(schema.tables[1]?.name).toBe('posts');
    });

    it('should extract validators from table definition', () => {
      const code = `
        import { defineSchema, defineTable } from 'convex/server';
        import { v } from 'convex/values';

        export default defineSchema({
          users: defineTable({
            name: v.string(),
            email: v.string(),
            age: v.number(),
          }),
        });
      `;

      const sourceFile = ts.createSourceFile(
        'schema.ts',
        code,
        ts.ScriptTarget.ES2022,
        true
      );

      const schema = parseSchema(sourceFile);

      expect(schema.tables).toHaveLength(1);
      const usersTable = schema.tables[0];
      expect(usersTable?.validators).toContain('name');
      expect(usersTable?.validators).toContain('email');
      expect(usersTable?.validators).toContain('age');
    });

    it('should extract index names from chained .index() calls', () => {
      const code = `
        import { defineSchema, defineTable } from 'convex/server';
        import { v } from 'convex/values';

        export default defineSchema({
          users: defineTable({
            name: v.string(),
            email: v.string(),
          })
            .index("by_email", ["email"])
            .index("by_name", ["name"]),
        });
      `;

      const sourceFile = ts.createSourceFile(
        'schema.ts',
        code,
        ts.ScriptTarget.ES2022,
        true
      );

      const schema = parseSchema(sourceFile);

      expect(schema.tables).toHaveLength(1);
      const usersTable = schema.tables[0];
      expect(usersTable?.indexes).toContain('by_email');
      expect(usersTable?.indexes).toContain('by_name');
    });

    it('should extract searchIndex names from chained .searchIndex() calls', () => {
      const code = `
        import { defineSchema, defineTable } from 'convex/server';
        import { v } from 'convex/values';

        export default defineSchema({
          posts: defineTable({
            title: v.string(),
            content: v.string(),
          })
            .searchIndex("search_content", {
              searchField: "content",
            }),
        });
      `;

      const sourceFile = ts.createSourceFile(
        'schema.ts',
        code,
        ts.ScriptTarget.ES2022,
        true
      );

      const schema = parseSchema(sourceFile);

      expect(schema.tables).toHaveLength(1);
      const postsTable = schema.tables[0];
      expect(postsTable?.indexes).toContain('search_content');
    });

    it('should extract vectorIndex names from chained .vectorIndex() calls', () => {
      const code = `
        import { defineSchema, defineTable } from 'convex/server';
        import { v } from 'convex/values';

        export default defineSchema({
          documents: defineTable({
            text: v.string(),
            embedding: v.array(v.float64()),
          })
            .vectorIndex("by_embedding", {
              vectorField: "embedding",
              dimensions: 1536,
            }),
        });
      `;

      const sourceFile = ts.createSourceFile(
        'schema.ts',
        code,
        ts.ScriptTarget.ES2022,
        true
      );

      const schema = parseSchema(sourceFile);

      expect(schema.tables).toHaveLength(1);
      const documentsTable = schema.tables[0];
      expect(documentsTable?.indexes).toContain('by_embedding');
    });

    it('should extract all index types from mixed chained calls', () => {
      const code = `
        import { defineSchema, defineTable } from 'convex/server';
        import { v } from 'convex/values';

        export default defineSchema({
          documents: defineTable({
            title: v.string(),
            content: v.string(),
            authorId: v.string(),
            embedding: v.array(v.float64()),
          })
            .index("by_author", ["authorId"])
            .searchIndex("search_content", {
              searchField: "content",
            })
            .vectorIndex("by_embedding", {
              vectorField: "embedding",
              dimensions: 1536,
            })
            .index("by_title", ["title"]),
        });
      `;

      const sourceFile = ts.createSourceFile(
        'schema.ts',
        code,
        ts.ScriptTarget.ES2022,
        true
      );

      const schema = parseSchema(sourceFile);

      expect(schema.tables).toHaveLength(1);
      const documentsTable = schema.tables[0];
      expect(documentsTable?.indexes).toHaveLength(4);
      expect(documentsTable?.indexes).toContain('by_author');
      expect(documentsTable?.indexes).toContain('search_content');
      expect(documentsTable?.indexes).toContain('by_embedding');
      expect(documentsTable?.indexes).toContain('by_title');
    });

    it('should handle tables without indexes', () => {
      const code = `
        import { defineSchema, defineTable } from 'convex/server';
        import { v } from 'convex/values';

        export default defineSchema({
          simple: defineTable({
            value: v.string(),
          }),
        });
      `;

      const sourceFile = ts.createSourceFile(
        'schema.ts',
        code,
        ts.ScriptTarget.ES2022,
        true
      );

      const schema = parseSchema(sourceFile);

      expect(schema.tables).toHaveLength(1);
      const simpleTable = schema.tables[0];
      expect(simpleTable?.indexes).toHaveLength(0);
      expect(simpleTable?.validators).toContain('value');
    });

    it('should return empty schema when no defineSchema is present', () => {
      const code = `
        const foo = 'bar';
      `;

      const sourceFile = ts.createSourceFile(
        'test.ts',
        code,
        ts.ScriptTarget.ES2022,
        true
      );

      const schema = parseSchema(sourceFile);

      expect(schema.tables).toHaveLength(0);
    });
  });
});
