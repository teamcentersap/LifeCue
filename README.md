# LifeCue Development Documents

This package contains the current LifeCue product and engineering
contract.

## Files

-   `AGENTS.md` --- rules for AI coding agents.
-   `LIFECUE_PRODUCT_SPEC.md` --- product, UX, architecture, scope, and
    module specification.
-   `LIFECUE_TEST_CASES.md` --- test cases and acceptance criteria.
-   `LIFECUE_CURSOR_PROMPTS.md` --- Cursor master prompt and Sprint 1--9
    prompts.
-   `LIFECUE_CODEX_PROMPTS.md` --- Codex architecture/review prompts.

## Current V1 Architectural Decision

LifeCue is **local-first**.

V1 uses: - SwiftUI - Apple Vision OCR - local deterministic extraction -
local persistence - local notifications - native iOS sharing for Forward

V1 does NOT use: - cloud AI - paid AI APIs - backend - PostgreSQL -
incoming Share Extension - WhatsApp/Gmail APIs

## Development sequence

1.  Cursor reads all documents and produces an architecture plan.
2.  Human reviews the plan.
3.  Cursor implements Sprint 1.
4.  Codex reviews Sprint 1.
5.  Continue Sprint 2 → Sprint 9.
6.  Run the complete test suite before TestFlight.

## Important

The documents intentionally separate: - product decisions - engineering
constraints - test acceptance - Cursor implementation prompts - Codex
review prompts

If implementation changes a product decision, update the specification
and tests before proceeding.
