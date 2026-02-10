---
name: gradle-format
description: Format and modernize Gradle build files according to Gradle 8+ best practices. Use when asked to format, clean up, or modernize build.gradle files.
license: MIT
compatibility: Claude Code
allowed-tools: Bash, Read, Glob, Grep, Edit, Write
---

# Gradle Build Files Formatter & Modernizer

## Purpose

Reformat, reorder, and optimize Gradle build files according to Gradle 8+ best practices. Handles dependency migration to version catalogs, proper quote usage, block ordering, and gradle.properties optimization.

## When to Use This Skill

Use when the user asks to:
- Format or clean up a Gradle build file
- Modernize build.gradle to Gradle 8+ syntax
- Migrate dependencies to version catalog (libs.versions.toml)
- Reorder Gradle file blocks
- Optimize gradle.properties

Trigger phrases: "format gradle", "clean up build.gradle", "modernize gradle", "fix gradle formatting", "gradle best practices"

## Commands

| Command | Description |
|---------|-------------|
| `/format:gradle` | Format current or specified Gradle file |
| `/format:gradle build.gradle` | Format specific file |

## Workflow

### Phase 1: Dependency Migration to Version Catalog

**Before formatting**, analyze dependencies and migrate to `gradle/libs.versions.toml`:

1. Extract versions from `build.gradle` not in `libs.versions.toml`
2. Convert dependencies to catalog references:
   - `implementation 'com.example:library:1.0.0'` → `implementation libs.example.library`
   - `id 'com.example.plugin' version '1.0.0'` → `alias(libs.plugins.example.plugin)`

**EXCEPTIONS - Do NOT migrate:**
- Template string dependencies: `"com.example:my-library:${myLibVersion}"`
- Local project dependencies: `implementation project(':submodule')`
- File dependencies: `implementation files('libs/local.jar')`
- Path references with variables: `apply from: "$rootDir/gradle/common.gradle"`

**Version Catalog Format:**
```toml
[versions]
exampleLib = "1.0.0"

[libraries]
example-library = { module = "com.example:library", version.ref = "exampleLib" }

[plugins]
example-plugin = { id = "com.example.plugin", version.ref = "exampleLib" }
```

### Phase 2: Formatting Rules

Apply WITHOUT changing logic:

1. **String Quotes:**
   - Single quotes `'` for plain text: `'check'`, `'com.example:library:1.0.0'`
   - Double quotes `"` ONLY with `$` interpolation: `"${xpVersion}"`, `"$rootDir/gradle"`
   - Rule: Contains `$` → double quotes, otherwise → single quotes

2. **Whitespace:**
   - Space inside parentheses: `tasks.named( 'check' )`
   - Space inside closure braces: `outputs.cacheIf { false }`
   - Space after keywords: `if (condition)`
   - No space before property access: `base.archivesName.get()`

3. **Modern Syntax:**
   - `tasks.named( 'taskName' ).configure { }` instead of redefining
   - `tasks.register( 'newTask', TaskType ) { }` for new tasks
   - Property API: `base { archivesName = 'name' }`

### Phase 3: Block Reordering

Reorder in this EXACT sequence (skip missing blocks):

1. Build Script (`buildscript {}`)
2. Plugins
3. External Scripts (`apply from:`, `apply plugin:`)
4. Project Metadata (`group`, `version`, `base {}`)
5. Extra Properties (`ext {}`)
6. Repositories
7. Global Configurations (`java {}`)
8. Source Sets
9. Configurations (custom)
10. Dependencies
11. Plugin-Specific Configurations (`node {}`)
12. Task Registrations (grouped by purpose)
13. Task Configurations (`tasks.named().configure {}`)
14. Lifecycle Wiring
15. Artifacts
16. Component Configuration
17. Publishing

### Phase 4: gradle.properties Optimization

Add if not present:
```properties
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.daemon=true
# org.gradle.configuration-cache=true  # Uncomment if supported
```

## Output Format

1. **For build.gradle:** Output complete reformatted file
2. **For libs.versions.toml additions:** Show separate block with new entries
3. **For gradle.properties:** Show only new optimization flags

## Quick Quote Reference

| String Type | Example | Use |
|------------|---------|-----|
| Plain text | `'verification'`, `'com.example:lib:1.0'` | Single `'` |
| With variables | `"${xpVersion}"`, `"$buildDir/output"` | Double `"` |
| Mixed content | `"build:${env}"` | Double `"` |
| Plain paths | `'src/main/java'` | Single `'` |
| Variable paths | `"$rootDir/gradle"` | Double `"` |

## Important Rules

- **NEVER** modify build logic or change dependency versions
- **PRESERVE** all custom functions and helper methods
- **MAINTAIN** informational comments
- **RESPECT** project-specific conventions
- **TEST** mentally that reformatted code compiles identically

## Keywords

gradle, build.gradle, formatting, modernize, version catalog, libs.versions.toml, gradle 8, best practices
