# @json-render/core

**Predictable. Guardrailed. Fast.** Core library for safe, user-prompted UI generation.

## Features

- **Conditional Visibility**: Show/hide components based on data paths, auth state, or complex logic expressions
- **Rich Actions**: Actions with typed parameters, confirmation dialogs, and success/error callbacks
- **Enhanced Validation**: Built-in validation functions with custom catalog functions support
- **Type-Safe Catalog**: Define component schemas using Zod for full type safety
- **Framework Agnostic**: Core logic is independent of UI frameworks

## Installation

```bash
npm install @json-render/core
# or
pnpm add @json-render/core
```

## Quick Start

### Create a Catalog

```typescript
import { createCatalog } from '@json-render/core';
import { z } from 'zod';

const catalog = createCatalog({
  name: 'My Dashboard',
  components: {
    Card: {
      props: z.object({
        title: z.string(),
        description: z.string().nullable(),
      }),
      hasChildren: true,
      description: 'A card container',
    },
    Button: {
      props: z.object({
        label: z.string(),
        action: ActionSchema,
      }),
      description: 'A clickable button',
    },
  },
  actions: {
    submit: { description: 'Submit the form' },
    export: { 
      params: z.object({ format: z.enum(['csv', 'pdf']) }),
      description: 'Export data',
    },
  },
  functions: {
    customValidation: (value) => typeof value === 'string' && value.length > 0,
  },
});
```

### Visibility Conditions

```typescript
import { visibility, evaluateVisibility } from '@json-render/core';

// Simple path-based visibility
const element1 = {
  key: 'error-banner',
  type: 'Alert',
  props: { message: 'Error!' },
  visible: { path: '/form/hasError' },
};

// Auth-based visibility
const element2 = {
  key: 'admin-panel',
  type: 'Card',
  props: { title: 'Admin' },
  visible: { auth: 'signedIn' },
};

// Complex logic
const element3 = {
  key: 'notification',
  type: 'Alert',
  props: { message: 'Warning' },
  visible: {
    and: [
      { path: '/settings/notifications' },
      { not: { path: '/user/dismissed' } },
      { gt: [{ path: '/items/count' }, 10] },
    ],
  },
};

// Evaluate visibility
const isVisible = evaluateVisibility(element1.visible, {
  dataModel: { form: { hasError: true } },
});
```

### Rich Actions

```typescript
import { resolveAction, executeAction } from '@json-render/core';

const buttonAction = {
  name: 'refund',
  params: {
    paymentId: { path: '/selected/id' },
    amount: 100,
  },
  confirm: {
    title: 'Confirm Refund',
    message: 'Refund $100 to customer?',
    variant: 'danger',
  },
  onSuccess: { navigate: '/payments' },
  onError: { set: { '/ui/error': '$error.message' } },
};

// Resolve dynamic values
const resolved = resolveAction(buttonAction, dataModel);
```

### Validation

```typescript
import { runValidation, check } from '@json-render/core';

const config = {
  checks: [
    check.required('Email is required'),
    check.email('Invalid email'),
    check.maxLength(100, 'Too long'),
  ],
  validateOn: 'blur',
};

const result = runValidation(config, {
  value: 'user@example.com',
  dataModel: {},
});

// result.valid = true
// result.errors = []
```

## API Reference

### Visibility

- `evaluateVisibility(condition, context)` - Evaluate a visibility condition
- `evaluateLogicExpression(expr, context)` - Evaluate a logic expression
- `visibility.*` - Helper functions for creating visibility conditions

### Actions

- `resolveAction(action, dataModel)` - Resolve dynamic values in an action
- `executeAction(context)` - Execute an action with callbacks
- `interpolateString(template, dataModel)` - Interpolate `${path}` in strings

### Validation

- `runValidation(config, context)` - Run validation checks
- `runValidationCheck(check, context)` - Run a single validation check
- `builtInValidationFunctions` - Built-in validators (required, email, min, max, etc.)
- `check.*` - Helper functions for creating validation checks

### Catalog

- `createCatalog(config)` - Create a catalog with components, actions, and functions
- `generateCatalogPrompt(catalog)` - Generate an AI prompt describing the catalog

## Types

See `src/types.ts` for full type definitions:

- `UIElement` - Base element structure
- `UITree` - Flat tree structure
- `VisibilityCondition` - Visibility condition types
- `LogicExpression` - Logic expression types
- `Action` - Rich action definition
- `ValidationConfig` - Validation configuration
