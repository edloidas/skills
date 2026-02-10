# Biome vs ESLint Rule Overlap

Rules that Biome handles, allowing ESLint to disable them for better performance.

## TypeScript ESLint Rules Biome Covers

These `@typescript-eslint/*` rules can be disabled when using Biome:

```javascript
// eslint.config.js - disable these when using Biome
rules: {
  '@typescript-eslint/no-explicit-any': 'off',
  '@typescript-eslint/prefer-for-of': 'off',
  '@typescript-eslint/prefer-optional-chain': 'off',
  '@typescript-eslint/no-inferrable-types': 'off',
  '@typescript-eslint/array-type': 'off',
  '@typescript-eslint/prefer-function-type': 'off',
  '@typescript-eslint/no-empty-function': 'off',
  '@typescript-eslint/no-empty-interface': 'off',
  '@typescript-eslint/no-unused-vars': 'off',
  '@typescript-eslint/no-non-null-assertion': 'off',
  '@typescript-eslint/consistent-type-imports': 'off',
  '@typescript-eslint/consistent-type-definitions': 'off',
  '@typescript-eslint/no-namespace': 'off',
  '@typescript-eslint/no-useless-constructor': 'off',
  '@typescript-eslint/no-empty-object-type': 'off',
}
```

## Core ESLint Rules Biome Covers

```javascript
rules: {
  // Possible Problems
  'no-debugger': 'off',
  'no-duplicate-case': 'off',
  'no-empty': 'off',
  'no-extra-boolean-cast': 'off',
  'no-fallthrough': 'off',
  'no-self-assign': 'off',
  'no-unused-labels': 'off',
  'no-useless-catch': 'off',
  'no-useless-rename': 'off',
  'no-with': 'off',

  // Suggestions
  'eqeqeq': 'off',
  'no-eval': 'off',
  'no-var': 'off',
  'prefer-const': 'off',
  'prefer-rest-params': 'off',
  'prefer-template': 'off',
}
```

## React Rules Biome Covers

```javascript
rules: {
  'react/jsx-key': 'off',
  'react/jsx-no-comment-textnodes': 'off',
  'react/jsx-no-duplicate-props': 'off',
  'react/jsx-no-useless-fragment': 'off',
  'react/no-children-prop': 'off',
  'react/no-danger-with-children': 'off',
  'react/void-dom-elements-no-children': 'off',
}
```

## Formatting (Always Let Biome Handle)

Biome is significantly faster for formatting. Disable all ESLint formatting:

```javascript
rules: {
  // All formatting rules should be off
  'indent': 'off',
  'quotes': 'off',
  'semi': 'off',
  'comma-dangle': 'off',
  'max-len': 'off',
  // ... etc
}
```

Or use `eslint-config-prettier` / disable stylistic rules entirely.

## Import Sorting

Biome handles import sorting. Disable:
- `eslint-plugin-import` ordering rules
- `eslint-plugin-simple-import-sort`

```javascript
rules: {
  'import/order': 'off',
  'sort-imports': 'off',
}
```

## Rules ESLint Should Keep

These provide value beyond what Biome offers:

### Type-Aware Rules (ESLint only)
```javascript
rules: {
  '@typescript-eslint/no-floating-promises': 'error',
  '@typescript-eslint/no-misused-promises': 'error',
  '@typescript-eslint/await-thenable': 'error',
  '@typescript-eslint/no-unnecessary-type-assertion': 'error',
  '@typescript-eslint/strict-boolean-expressions': 'error',
}
```

### React Hooks (ESLint only)
```javascript
rules: {
  'react-hooks/rules-of-hooks': 'error',
  'react-hooks/exhaustive-deps': 'warn',
}
```

### Accessibility (ESLint only)
```javascript
rules: {
  'jsx-a11y/alt-text': 'error',
  'jsx-a11y/aria-props': 'error',
  'jsx-a11y/click-events-have-key-events': 'error',
  // ... other a11y rules
}
```

## Configuration Template

When using both Biome and ESLint:

```javascript
// eslint.config.js
import tseslint from 'typescript-eslint';
import jsxA11y from 'eslint-plugin-jsx-a11y';

export default tseslint.config(
  // Ignores
  { ignores: ['node_modules/', 'dist/', '**/*.d.ts'] },

  // TypeScript with type-aware rules only
  ...tseslint.configs.strictTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        projectService: true,
      },
    },
    rules: {
      // Disable rules Biome handles
      '@typescript-eslint/no-explicit-any': 'off',
      '@typescript-eslint/prefer-for-of': 'off',
      '@typescript-eslint/prefer-optional-chain': 'off',
      '@typescript-eslint/no-inferrable-types': 'off',
      '@typescript-eslint/array-type': 'off',
      '@typescript-eslint/prefer-function-type': 'off',
      '@typescript-eslint/no-empty-function': 'off',
      '@typescript-eslint/no-empty-interface': 'off',
      '@typescript-eslint/no-unused-vars': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
      '@typescript-eslint/consistent-type-imports': 'off',
      '@typescript-eslint/consistent-type-definitions': 'off',
    },
  },

  // Accessibility (ESLint only)
  jsxA11y.flatConfigs.recommended,
);
```

## Biome Configuration

```json
// biome.json
{
  "$schema": "https://biomejs.dev/schemas/1.9.4/schema.json",
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "correctness": {
        "noUnusedImports": "error",
        "noUnusedVariables": "error"
      },
      "style": {
        "noNonNullAssertion": "warn",
        "useConst": "error"
      }
    }
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2
  },
  "organizeImports": {
    "enabled": true
  }
}
```
