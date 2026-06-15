# swift-postgres-models

A SwiftPM build tool plugin that generates typed PostgreSQL query helpers and a migration runner from plain SQL files. Write SQL, get type-safe Swift.

No ORM. No DSL. No runtime library. The generated code talks directly to [PostgresNIO](https://github.com/vapor/postgres-nio).

## How it works

Add `.query.sql` and `.migration.sql` files to your target. At build time, the plugin generates a `<Name>Queries` struct per query file and a single `Migrations` struct for all migration files. The generated Swift is compiled as part of your target — no extra dependencies beyond PostgresNIO.

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/wendylabsinc/swift-postgres-models.git", from: "1.0.0"),
    .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
],
targets: [
    .executableTarget(
        name: "MyApp",
        dependencies: [
            .product(name: "PostgresNIO", package: "postgres-nio"),
        ],
        plugins: [
            .plugin(name: "PostgresModelsPlugin", package: "swift-postgres-models"),
        ]
    ),
]
```

**Requirements:** Swift 6, macOS 14+

## Queries

Create a file with the `.query.sql` extension anywhere in your target's source directory. Annotate each query with comments:

```sql
-- @query GetUser :one
-- @param id: UUID
-- @returns id: UUID, name: String, email: String?
SELECT id, name, email FROM users WHERE id = $1;

-- @query ListUsers :many
-- @returns id: UUID, name: String, email: String?
SELECT id, name, email FROM users ORDER BY name;

-- @query CreateUser :exec
-- @param id: UUID
-- @param name: String
-- @param email: String?
INSERT INTO users (id, name, email) VALUES ($1, $2, $3);
```

From `users.query.sql`, the plugin generates `UsersQueries` with static methods:

```swift
// :one — returns the first row or nil
let user = try await UsersQueries.getUser(client, id: id, logger: logger)

// :many — returns an array
let users = try await UsersQueries.listUsers(client, logger: logger)

// :exec — no return value
try await UsersQueries.createUser(client, id: id, name: name, email: email, logger: logger)
```

### Transactions

Each generated function takes `some PostgresQueryRunner` as its first argument. Both `PostgresClient` and `PostgresConnection` conform, so you can run a single query against the pooled client (one connection per call) **or** run several queries atomically against one connection inside a transaction:

```swift
try await client.withTransaction(logger: logger) { connection in
    try await UsersQueries.createUser(connection, id: id, name: name, email: email, logger: logger)
    try await AccountsQueries.createAccount(connection, userId: id, logger: logger)
}
```

Because every call inside the closure shares the same `connection`, they run in the same transaction and commit or roll back together. Passing `client` instead would lease a separate connection per call, so those calls would **not** share a transaction.

### Annotation reference

| Annotation | Format | Notes |
|------------|--------|-------|
| `@query` | `-- @query <Name> :<kind>` | Required. Starts a query block. |
| `@param` | `-- @param <name>: <Type>` | One per `$1`, `$2`, … placeholder, in order. |
| `@returns` | `-- @returns <name>: <Type>, …` | Required for `:one` and `:many`. Single comma-separated line. |

**Kinds:**
- `:one` — `async throws -> T?` — returns the first row, or `nil`
- `:many` — `async throws -> [T]` — collects all rows into an array
- `:exec` — `async throws -> Void` — no return value

**Supported types:** `UUID`, `String`, `Int`, `Int64`, `Double`, `Decimal`, `Bool`, `Date`, `Data` (`bytea`), and optionals of each (`UUID?`, `String?`, etc.)

**Array types:** `[UUID]`, `[String]`, `[Int]`, `[Int64]`, `[Double]`, `[Bool]`, `[Date]` (and optionals). Write them directly (`[UUID]`) or with the SQL spelling (`UUID[]`, `INT[]`, `BIGINT[]`, `TEXT[]`, …). Use arrays for `= ANY($1)` membership tests and `unnest(...)` bulk inserts:

```sql
-- @query UsersByIDs :many
-- @param ids: [UUID]
-- @returns id: UUID, name: String
SELECT id, name FROM users WHERE id = ANY($1);

-- @query InsertVarieties :exec
-- @param ids: [UUID]
-- @param names: [String]
INSERT INTO varieties (id, name) SELECT * FROM unnest($1::uuid[], $2::text[]);
```

```swift
let found = try await UsersQueries.usersByIDs(client, ids: ids, logger: logger)
try await VarietiesQueries.insertVarieties(client, ids: ids, names: names, logger: logger)
```

**File → struct naming:** the file stem is split on `_` and `-`, each word capitalised, then joined with a `Queries` suffix. `todo_items.query.sql` → `TodoItemsQueries`.

**SQL injection safety:** PostgresNIO's `PostgresQuery` string interpolation is used for all parameters — `\(value)` binds the value as a prepared statement parameter, never raw-interpolated into the query string.

### Enum / RawRepresentable types

For columns stored as `text` or `int` that map to a Swift enum, declare the enum type directly in `@param`/`@returns`. The type must be a `RawRepresentable` defined in your module (`String`- or `Int`-backed):

```swift
enum Visibility: String { case `public`, unlisted, `private` }
```

```sql
-- @query SetVisibility :exec
-- @param id: UUID
-- @param visibility: Visibility
UPDATE events SET visibility = $2 WHERE id = $1;

-- @query GetVisibility :one
-- @param id: UUID
-- @returns visibility: Visibility
SELECT visibility FROM events WHERE id = $1;
```

The generator binds parameters via `.rawValue` and decodes results by reading the raw column value and calling `init(rawValue:)`. The backing type defaults to `String`; for an `Int`-backed enum, append `= Int`:

```sql
-- @returns level: PriorityLevel = Int
```

A non-optional column whose stored value matches no enum case throws `PostgresModelsError.invalidRawValue`; an optional enum return (`Visibility?`) instead decodes to `nil`. Any type name starting with an uppercase letter that isn't a built-in supported type is treated as a custom `RawRepresentable` type — a typo will surface as a Swift compile error in the generated code.

## Migrations

Create files with the `.migration.sql` extension. No annotations needed — just plain SQL:

```sql
-- 001_create_users.migration.sql
CREATE TABLE users (
    id    UUID PRIMARY KEY,
    name  TEXT NOT NULL,
    email TEXT
);
```

Files are sorted lexicographically before embedding, so numeric prefixes control order. All migrations across all `.migration.sql` files in your target are combined into a single `Migrations.swift`.

At app startup, call:

```swift
try await Migrations.run(client: client, logger: logger)
```

The runner creates a `postgres_models_migrations` tracking table on first run, then applies each migration exactly once inside a transaction. Already-applied migrations are skipped.

## Example

A working todo app is in [`Examples/TodoApp`](Examples/TodoApp). It demonstrates migrations, all three query kinds, and environment-variable-based connection config.

```bash
# Start Postgres
docker run --rm -d \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=password \
  -e POSTGRES_DB=todos \
  -p 5432:5432 \
  postgres:16

# Run the example
cd Examples/TodoApp
PGPASSWORD=password swift run
```

## Error handling

Build errors are reported with file and line context. Common mistakes caught at build time:

| Error | Cause |
|-------|-------|
| `missing query kind` | `@query` line has no `:one`, `:many`, or `:exec` |
| `unknown query kind` | Typo in the kind |
| `param count mismatch` | Number of `@param` lines doesn't match `$N` placeholders in the SQL |
| `unsupported type` | A type in `@param` or `@returns` isn't in the supported list |
| `query '…' has no @returns` | `:one` or `:many` query is missing an `@returns` line |
| `query '…' has no SQL body` | Annotations present but no SQL statement follows |
