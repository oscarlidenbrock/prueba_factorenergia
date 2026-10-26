# Project instructions

## Scope and sources

- Complete the electricity retailer technical assessment: `parte1/` is a PHP REST API for meter readings; `parte2/` is a SQL Server billing incident investigation. The exercises are independent.
- Implement only the requested step. Prioritize a small, working, explainable solution. The assessment sets no stated time limit; do not import the previous assessment's 90-minute target.
- Read the general README and the relevant part's README before implementation. Locate the supplied documentation in the actual repository, including `docs/` when applicable; do not invent paths or missing requirements.
- Distinguish explicit requirements, implementation decisions, optional improvements, and unresolved business questions. Do not rewrite the assignment to match the implementation.
- Preserve the supplied `parte1/` and `parte2/` folders. Keep the original SQL initialization data and Jenkins logs as reproducible evidence. Add corrective scripts or migrations separately instead of hiding anomalies in the fixtures.
- Read relevant source files before changing them. Reuse unchanged documentation, schema findings, and checks already established in the session.

## Language and architecture

- Keep this file in English. Use English for new code identifiers, code comments, PHPDoc, test names, and Conventional Commits. Use Spanish for explanations, API messages, and delivery documentation.
- Preserve the supplied Spanish database table/column names and domain values, including `activo`, `baja`, `real`, and `estimada`. Do not translate existing schema objects to satisfy naming preferences.
- Part 1 targets PHP 8.3 and Yii2, the preferred framework in the assignment. Use another framework only after an explicit project decision and explain the reason in `parte1/SOLUCION.md`.
- Follow Yii2 conventions with focused controllers, input validation models, and a small service where transactional business rules warrant it. Use Active Record, Query Builder, or parameterized commands deliberately; generic repositories and extra abstraction layers are not required.
- Apply KISS, YAGNI, and SOLID pragmatically. Do not introduce a frontend, authentication system, queues, caching, full DDD, CQRS, or unrelated integrations without a concrete requirement or agreed need.
- Use explicit PHP parameter/return types and strict typing in new application files where appropriate. Document useful array shapes and non-obvious business rules; avoid redundant comments and blanket error suppressions.
- Routine files, configuration changes, and dependencies necessary for the agreed Yii2 implementation and meaningful tests are authorized. Explain significant additions; ask only when a choice materially changes scope or architecture.

## Environment and dependencies

- Use the supplied Docker Compose environments and SQL Server 2022. Run PHP, Composer, and application checks inside the `parte1` app container to match the provided PHP/extensions rather than relying on macOS PHP.
- Inspect `compose.yaml` and `app/Dockerfile` before prescribing commands. During initial setup the app may not have a long-running command; use `docker compose run --rm --no-deps app ...` when appropriate and the database is ready.
- Part 1: from the app container use `db:1433`, database `lecturas`; from macOS use `localhost:14331`. Part 2: from macOS use `localhost:14332`, database `facturacion`. Do not confuse host ports with container ports.
- Wait for database health and successful `db-init` completion before dependent checks. The two parts do not need to run simultaneously.
- Retain `linux/amd64` for the SQL Server services. Account for the assignment's Apple Silicon/Rosetta requirement when relevant.
- Verify the actual volume configuration before resetting services. The supplied Part 1 configuration has no database persistence volume: removing the database container can lose its changes. Never imply that `docker compose down` preserves that database.
- Keep build/startup reproducible from a clean checkout. Install from `composer.lock` during normal setup; update dependencies deliberately. Do not make a production-ready web-server deployment a prerequisite for this assessment.
- Use environment configuration for application connection settings and document safe development defaults/examples. The supplied demo credentials belong to the exercise; never reuse them for real systems or commit real credentials.
- Check resolved dependency versions from Composer/lockfiles. Consult official documentation for unfamiliar or version-sensitive APIs. Never hand-edit `vendor/`, lockfile dependency resolutions, or generated output to conceal incompatibilities.

## Part 1: contract and validation

- Define and document the endpoint, HTTP method, JSON field names/types, date format, status codes, error shape, and retry behavior. Accept at least CUPS, reading date, cumulative kWh, and real/estimated type.
- Keep input validation server-side. Reject malformed JSON, missing/invalid fields, invalid calendar dates, and unsupported reading types with useful responses; never silently coerce incompatible JSON types.
- Align numeric validation with the supplied integer `lectura_kwh` column and `digitos_contador`, including zero and maximum values. Do not introduce decimal precision or schema changes without justification.
- Resolve the contract using CUPS and the reading date. CUPS is not a unique contract identifier: the supplied contracts 12 and 24 share a CUPS with successive validity periods. Never choose an arbitrary first match.
- Enforce both the contract's status and its validity dates. A contract marked `baja` does not accept new readings, including historical dates within its former validity. An `activo` status alone is insufficient: contract 25 starts in the future.
- Document inclusive/exclusive date boundaries. Reject ambiguous overlapping contracts rather than choosing silently. Define any future-reading policy explicitly and keep tests independent of the wall clock.
- Treat kWh as a cumulative meter value, not period consumption. A lower value can reflect meter rollover or an earlier overestimate; do not impose unconditional monotonicity without an explicit supported rule. Receiving readings does not require implementing billing or regularization.
- Explain rejected readings clearly and ensure they are not persisted. Do not expose SQL, stack traces, credentials, or customer personal data in API errors.

## Part 1: retries and persistence

- Define the identity of an identical reading and distinguish an exact retry from a different value/type for the same contract and date. Document conflict handling and any estimated-to-real replacement policy rather than silently overwriting data.
- An exact retry must not insert another row or change the original reception timestamp. Return an understandable successful repeat response when the previously accepted reading can be identified; document replay behavior if contract status has changed since acceptance.
- Protect idempotency under concurrent requests. A standalone SELECT-before-INSERT check is insufficient. Use an appropriate database constraint and/or transaction-locking strategy, explain it, and verify it against SQL Server.
- The seed already contains duplicate readings 121 and 137. Inspect existing duplicates before introducing uniqueness; do not delete or alter them silently to make a migration pass. Document how the chosen approach handles historical duplicates.
- Make dependent checks and writes atomic where consistency requires it. Revalidate relevant state under appropriate locking and roll back on failure. Use bound parameters and explicitly selected writable fields.
- Set reception timestamps on the server using a documented consistent timezone, preferably UTC. Do not expose SQL details, stack traces, credentials, or customer personal data in API errors.

## Part 2: investigation and evidence

- Read the supplied schema, `sp_facturar_periodo`, initialization data, and Jenkins logs before proposing causes. Investigate the September 2026 billing run launched on October 5 and compare with April-August where relevant.
- Do not infer the root cause from complaints alone. Trace relationships among contracts, readings, tariff price validity, invoices, process executions, and source files. Distinguish duplicated invoice rows from duplicated delivery or collection, which the available data may not prove.
- Keep diagnostic scripts read-only and reproducible on a freshly initialized `facturacion` database. Include the relevant period as an explicit parameter where useful.
- Support findings with affected IDs, detection queries, counts, and financial impact where determinable. Separate clients, contracts, invoices, and excess charges; avoid counting the same affected client multiple times across causes.
- Use the assignment's simplified calculation without taxes: consumption multiplied by the applicable kWh price, plus the monthly fixed term. Verify price validity and reading semantics from evidence before calculating corrections.
- Clearly separate confirmed facts, hypotheses, limitations, and business decisions. Do not invent charges, refunds, customer communications, or externally completed actions.

## Part 2: correction and prevention

- Deliver separate, clearly ordered SQL scripts for diagnosis, correction, and prevention, with exact execution instructions for SQL Server 2022. Respect T-SQL batches and client-specific commands such as `GO`.
- Provide a read-only preview/dry-run of proposed changes, including affected IDs and before/after amounts where relevant. Make the write path explicit and executable in the assessment environment.
- Preserve audit evidence and original invoice identity. Do not silently delete issued invoices, rewrite historical readings/prices, invent historical timestamps, or assume which duplicate should survive without justification.
- When correction depends on unresolved business policy, expose that decision, document a provisional assumption or approved-case scope, and leave ambiguous rows unchanged. Still implement safe, deterministic corrections supported by the evidence.
- Use explicit transactions, appropriate error handling such as `SET XACT_ABORT ON` with TRY/CATCH, and precondition checks for mutations. Avoid leaving an open transaction or partial repair after failure.
- Make correction and prevention scripts safe to repeat, including after a previous successful run. Recheck current data before mutation and prevent duplicate corrective entries or adjustments.
- Address demonstrated causes through procedure changes, uniqueness, execution controls, validation, and/or focused monitoring as appropriate. Do not apply a blanket uniqueness rule that blocks legitimate adjustments or credit notes without considering the data model.
- Do not execute destructive resets or broad data cleanup without explicit authorization. Normal scoped development writes and correction-script execution are permitted on a verified disposable assessment/test database when requested by the current task.

## Verification

- Use a small, appropriate testing setup. Prefer HTTP/integration tests for API responses and persistence, with unit tests for isolated rules when useful. Do not install unrelated tooling or test every trivial wrapper.
- Cover successful real/estimated readings, malformed input, unknown CUPS, `baja` contracts, validity boundaries, future activation, shared CUPS, numeric limits, exact retries, conflicting submissions, and atomic failure where applicable.
- Verify concurrent retries and SQL Server-specific locking/constraints against SQL Server. SQLite or mocked results alone do not establish those guarantees.
- Verify the effective database target before tests or scripts that modify/reset data. Use an isolated test database or independently disposable Compose environment; never reset the developer's current working database implicitly.
- For Part 2, verify scripts on a fresh seed, compare before/after findings, and rerun correction/prevention to check repeatability. Check relevant normal cases remain valid, not just that anomalous counts decrease.
- Run relevant checks after changes and the full available suite before delivery. Use configured lint/format/static-analysis tools where present; do not add an elaborate quality pipeline solely for this exercise.
- Documentation-only edits need no new behavior tests. Never report checks as passed unless actually executed; distinguish verified results, manual checks, and environment blockers.

## Documentation and Git

- Keep the original assignment documentation available. Put Part 1 execution instructions, example requests/responses, main decisions, limitations, and next steps in `parte1/SOLUCION.md` or an equally clear documented location.
- Put Part 2 script order/commands and a brief business report in `parte2/INFORME.md` or an equally clear documented location. Explain what happened, who is affected, the proposed response, prevention, and decisions still required from business.
- Update the root README with concise navigation and common prerequisites when useful. Keep documentation limited to the deliverables requested by the assessment.
- Do not add AI prompt logs, tool-attribution documents, development journals, or other tracking records. The assessment permits AI and does not request these artifacts. If asked about assistance, describe actual contributions accurately.
- Use focused Conventional Commits in English. Commit only when requested; amend, push, and history changes require explicit authorization. Preserve unrelated user changes.
- Track `composer.json`, `composer.lock`, Docker configuration, SQL scripts, original Jenkins logs, and delivery documentation. Ignore dependencies, runtime/cache files, local settings, and real secrets. Do not ignore all `*.log` files because the supplied Jenkins log is evidence.
- Search with `rg`; batch independent reads/checks when safe and keep dependent edits sequential. Start with the smallest coherent implementation and broaden checks only to resolve a concrete concern.
- Report changes, checks, and unresolved issues concisely. Ask only when missing information materially affects scope, correctness, or irreversible data handling; continue routine authorized work without repeated confirmation.
