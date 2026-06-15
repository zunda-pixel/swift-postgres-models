import Testing
@testable import PostgresModelsGeneratorCore

struct SQLParserTests {
    // MARK: parseQueryFile — happy paths

    @Test func parsesOneQuery() throws {
        let input = """
            -- @query GetUser :one
            -- @param id: UUID
            -- @returns id: UUID, name: String
            SELECT id, name FROM users WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries.count == 1)
        let q = result.queries[0]
        #expect(q.name == "GetUser")
        #expect(q.kind == .one)
        #expect(q.params == [ParsedParam(name: "id", type: "UUID")])
        #expect(q.returns == [
            ParsedReturn(name: "id", type: "UUID"),
            ParsedReturn(name: "name", type: "String"),
        ])
        #expect(q.sql.contains("SELECT id, name FROM users WHERE id ="))
    }

    @Test func parsesManyQuery() throws {
        let input = """
            -- @query ListUsers :many
            -- @returns id: UUID, name: String
            SELECT id, name FROM users;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].kind == .many)
        #expect(result.queries[0].params.isEmpty)
    }

    @Test func parsesExecQuery() throws {
        let input = """
            -- @query DeleteUser :exec
            -- @param id: UUID
            DELETE FROM users WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].kind == .exec)
        #expect(result.queries[0].returns.isEmpty)
    }

    @Test func parsesMultipleQueriesInOneFile() throws {
        let input = """
            -- @query GetUser :one
            -- @param id: UUID
            -- @returns id: UUID
            SELECT id FROM users WHERE id = $1;

            -- @query ListUsers :many
            -- @returns id: UUID
            SELECT id FROM users;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries.count == 2)
        #expect(result.queries[0].name == "GetUser")
        #expect(result.queries[1].name == "ListUsers")
    }

    @Test func parsesOptionalTypes() throws {
        let input = """
            -- @query GetUser :one
            -- @param id: UUID
            -- @returns id: UUID, email: String?
            SELECT id, email FROM users WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[1].type == "String?")
    }

    @Test func emptyFileProducesEmptyResult() throws {
        let result = try SQLParser.parseQueryFile("")
        #expect(result.queries.isEmpty)
    }

    @Test func fileWithOnlyCommentsProducesEmptyResult() throws {
        let result = try SQLParser.parseQueryFile("-- just a comment\n-- another comment\n")
        #expect(result.queries.isEmpty)
    }

    // MARK: parseQueryFile — error cases

    @Test func throwsOnMissingKind() {
        let input = """
            -- @query GetUser
            -- @returns id: UUID
            SELECT id FROM users;
            """
        #expect(throws: SQLParserError.missingQueryKind(line: "-- @query GetUser")) {
            try SQLParser.parseQueryFile(input)
        }
    }

    @Test func throwsOnUnknownKind() {
        let input = """
            -- @query GetUser :fetch
            -- @returns id: UUID
            SELECT id FROM users;
            """
        #expect(throws: SQLParserError.unknownQueryKind("fetch")) {
            try SQLParser.parseQueryFile(input)
        }
    }

    @Test func throwsOnMissingReturnsForOne() {
        let input = """
            -- @query GetUser :one
            -- @param id: UUID
            SELECT id FROM users WHERE id = $1;
            """
        #expect(throws: SQLParserError.missingReturns(queryName: "GetUser")) {
            try SQLParser.parseQueryFile(input)
        }
    }

    @Test func throwsOnMissingReturnsForMany() {
        let input = """
            -- @query ListUsers :many
            SELECT id FROM users;
            """
        #expect(throws: SQLParserError.missingReturns(queryName: "ListUsers")) {
            try SQLParser.parseQueryFile(input)
        }
    }

    @Test func throwsOnUnsupportedParamType() {
        let input = """
            -- @query GetUser :one
            -- @param id: notatype
            -- @returns id: UUID
            SELECT id FROM users WHERE id = $1;
            """
        #expect(throws: SQLParserError.unsupportedType("notatype", queryName: "GetUser")) {
            try SQLParser.parseQueryFile(input)
        }
    }

    @Test func throwsOnUnsupportedReturnType() {
        let input = """
            -- @query GetUser :one
            -- @param id: UUID
            -- @returns id: notatype
            SELECT id FROM users WHERE id = $1;
            """
        #expect(throws: SQLParserError.unsupportedType("notatype", queryName: "GetUser")) {
            try SQLParser.parseQueryFile(input)
        }
    }

    @Test func throwsOnParamCountMismatch() {
        let input = """
            -- @query GetUser :one
            -- @param id: UUID
            -- @param name: String
            -- @returns id: UUID
            SELECT id FROM users WHERE id = $1;
            """
        #expect(throws: SQLParserError.paramCountMismatch(queryName: "GetUser", declared: 2, placeholders: 1)) {
            try SQLParser.parseQueryFile(input)
        }
    }

    @Test func throwsOnEmptySQLBody() {
        let input = """
            -- @query GetUser :one
            -- @param id: UUID
            -- @returns id: UUID
            """
        #expect(throws: SQLParserError.emptySQLBody(queryName: "GetUser")) {
            try SQLParser.parseQueryFile(input)
        }
    }

    @Test func throwsOnMultipleReturnsLines() {
        let input = """
            -- @query GetUser :one
            -- @param id: UUID
            -- @returns id: UUID
            -- @returns name: String
            SELECT id FROM users WHERE id = $1;
            """
        #expect(throws: SQLParserError.multipleReturnsLines(queryName: "GetUser")) {
            try SQLParser.parseQueryFile(input)
        }
    }

    @Test func parsesTextArrayType() throws {
        let input = """
            -- @query GetTags :one
            -- @param id: UUID
            -- @returns tags: TEXT[]
            SELECT tags FROM items WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[0].type == "[String]")
    }

    @Test func parsesOptionalTextArrayType() throws {
        let input = """
            -- @query GetTags :one
            -- @param id: UUID
            -- @returns tags: TEXT[]?
            SELECT tags FROM items WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[0].type == "[String]?")
    }

    @Test func parsesDirectStringArrayType() throws {
        let input = """
            -- @query GetTags :one
            -- @param id: UUID
            -- @returns tags: [String]
            SELECT tags FROM items WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[0].type == "[String]")
    }

    @Test func parsesUUIDArrayParam() throws {
        let input = """
            -- @query GetUsers :many
            -- @param ids: [UUID]
            -- @returns id: UUID
            SELECT id FROM users WHERE id = ANY($1);
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].params[0] == ParsedParam(name: "ids", type: "[UUID]"))
    }

    @Test func parsesSQLUUIDArrayTypeAsSwiftArray() throws {
        let input = """
            -- @query GetUsers :many
            -- @param ids: UUID[]
            -- @returns id: UUID
            SELECT id FROM users WHERE id = ANY($1);
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].params[0].type == "[UUID]")
    }

    @Test func parsesIntAndBigintArrayAliases() throws {
        let input = """
            -- @query Counts :many
            -- @param small: INT[]
            -- @param big: BIGINT[]
            -- @returns n: Int
            SELECT n FROM t WHERE a = ANY($1) AND b = ANY($2);
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].params[0].type == "[Int]")
        #expect(result.queries[0].params[1].type == "[Int64]")
    }

    @Test func parsesDirectArrayTypesForAllSupportedElements() throws {
        let input = """
            -- @query Bulk :exec
            -- @param a: [UUID]
            -- @param b: [Int]
            -- @param c: [Int64]
            -- @param d: [Double]
            -- @param e: [Bool]
            -- @param f: [Date]
            -- @param g: [String]
            INSERT INTO t SELECT * FROM unnest($1, $2, $3, $4, $5, $6, $7);
            """
        let result = try SQLParser.parseQueryFile(input)
        let types = result.queries[0].params.map { $0.type }
        #expect(types == ["[UUID]", "[Int]", "[Int64]", "[Double]", "[Bool]", "[Date]", "[String]"])
    }

    // MARK: Dynamic queries (optional-filter pattern)

    @Test func acceptsOptionalFilterPatternWithReusedPlaceholders() throws {
        // The documented dynamic-query pattern references each placeholder twice.
        let input = """
            -- @query ListEvents :many
            -- @param organizer_id: UUID?
            -- @param after: Date?
            -- @returns id: UUID, title: String
            SELECT id, title FROM events
            WHERE ($1::uuid IS NULL OR organizer_id = $1)
              AND ($2::timestamptz IS NULL OR starts_at > $2)
            ORDER BY starts_at;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].params == [
            ParsedParam(name: "organizer_id", type: "UUID?"),
            ParsedParam(name: "after", type: "Date?"),
        ])
    }

    // MARK: Custom (RawRepresentable) types

    @Test func parsesCustomEnumParam() throws {
        let input = """
            -- @query SetVisibility :exec
            -- @param id: UUID
            -- @param visibility: EventVisibility
            UPDATE events SET visibility = $2 WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        let p = result.queries[0].params[1]
        #expect(p == ParsedParam(name: "visibility", type: "EventVisibility", isCustom: true))
    }

    @Test func parsesCustomEnumReturnDefaultsToStringBacking() throws {
        let input = """
            -- @query GetVisibility :one
            -- @param id: UUID
            -- @returns visibility: EventVisibility
            SELECT visibility FROM events WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        let r = result.queries[0].returns[0]
        #expect(r == ParsedReturn(name: "visibility", type: "EventVisibility", isCustom: true, backing: "String"))
    }

    @Test func parsesCustomEnumReturnWithIntBacking() throws {
        let input = """
            -- @query GetPriority :one
            -- @param id: UUID
            -- @returns level: PriorityLevel = Int
            SELECT level FROM events WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        let r = result.queries[0].returns[0]
        #expect(r == ParsedReturn(name: "level", type: "PriorityLevel", isCustom: true, backing: "Int"))
    }

    @Test func parsesOptionalCustomEnumReturn() throws {
        let input = """
            -- @query GetStatus :one
            -- @param id: UUID
            -- @returns status: Status?
            SELECT status FROM participants WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        let r = result.queries[0].returns[0]
        #expect(r == ParsedReturn(name: "status", type: "Status?", isCustom: true, backing: "String"))
    }

    @Test func throwsOnUnsupportedBackingType() {
        let input = """
            -- @query GetX :one
            -- @param id: UUID
            -- @returns x: MyEnum = Float
            SELECT x FROM t WHERE id = $1;
            """
        #expect(throws: SQLParserError.unsupportedType("MyEnum = Float", queryName: "GetX")) {
            try SQLParser.parseQueryFile(input)
        }
    }

    @Test func lowercaseUnknownTypeStaysUnsupported() {
        // A lowercase unknown type is not a valid custom type, so it still errors.
        let input = """
            -- @query GetX :one
            -- @param id: UUID
            -- @returns x: mytype
            SELECT x FROM t WHERE id = $1;
            """
        #expect(throws: SQLParserError.unsupportedType("mytype", queryName: "GetX")) {
            try SQLParser.parseQueryFile(input)
        }
    }

    @Test func parsesByteaTypeAsData() throws {
        let input = """
            -- @query GetKey :one
            -- @param id: UUID
            -- @returns public_key: BYTEA
            SELECT public_key FROM passkey_credentials WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[0].type == "Data")
    }

    @Test func parsesOptionalByteaTypeAsOptionalData() throws {
        let input = """
            -- @query GetKey :one
            -- @param id: UUID
            -- @returns public_key: BYTEA?
            SELECT public_key FROM passkey_credentials WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[0].type == "Data?")
    }

    @Test func parsesDataParamType() throws {
        let input = """
            -- @query SaveKey :exec
            -- @param id: UUID
            -- @param public_key: Data
            INSERT INTO passkey_credentials (id, public_key) VALUES ($1, $2);
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].params[1] == ParsedParam(name: "public_key", type: "Data"))
    }

    @Test func parsesInetTypeAsString() throws {
        let input = """
            -- @query GetHost :one
            -- @param id: UUID
            -- @returns ip: INET
            SELECT ip FROM hosts WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[0].type == "String")
    }

    @Test func parsesOptionalInetTypeAsOptionalString() throws {
        let input = """
            -- @query GetHost :one
            -- @param id: UUID
            -- @returns ip: INET?
            SELECT ip FROM hosts WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[0].type == "String?")
    }

    @Test func parsesMacaddrTypeAsString() throws {
        let input = """
            -- @query GetDevice :one
            -- @param id: UUID
            -- @returns mac: MACADDR
            SELECT mac FROM devices WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[0].type == "String")
    }

    @Test func parsesJsonbTypeAsString() throws {
        let input = """
            -- @query GetMeta :one
            -- @param id: UUID
            -- @returns meta: JSONB
            SELECT meta FROM items WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[0].type == "String")
    }

    @Test func parsesJsonbParamTypeAsString() throws {
        let input = """
            -- @query UpsertMeta :exec
            -- @param id: UUID
            -- @param meta: JSONB
            UPDATE items SET meta = $2 WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].params[1].type == "String")
    }

    @Test func parsesJsonTypeAsString() throws {
        let input = """
            -- @query GetMeta :one
            -- @param id: UUID
            -- @returns meta: JSON
            SELECT meta FROM items WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[0].type == "String")
    }

    // MARK: Int64 / BIGINT tests

    @Test func parsesBigintAsInt64() throws {
        let input = """
            -- @query GetOrder :one
            -- @param id: BIGINT
            -- @returns id: BIGINT, total: BIGINT
            SELECT id, total FROM orders WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].params[0].type == "Int64")
        #expect(result.queries[0].returns[0].type == "Int64")
        #expect(result.queries[0].returns[1].type == "Int64")
    }

    @Test func parsesOptionalBigintAsOptionalInt64() throws {
        let input = """
            -- @query GetOrder :one
            -- @param id: UUID
            -- @returns parent_id: BIGINT?
            SELECT parent_id FROM orders WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[0].type == "Int64?")
    }

    @Test func parsesBigserialAsInt64() throws {
        let input = """
            -- @query GetOrder :one
            -- @param id: UUID
            -- @returns id: BIGSERIAL
            SELECT id FROM orders WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[0].type == "Int64")
    }

    @Test func parsesInt8AsInt64() throws {
        let input = """
            -- @query GetOrder :one
            -- @param id: UUID
            -- @returns id: INT8
            SELECT id FROM orders WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[0].type == "Int64")
    }

    // MARK: Decimal / NUMERIC tests

    @Test func parsesNumericAsDecimal() throws {
        let input = """
            -- @query GetPrice :one
            -- @param id: UUID
            -- @returns price: NUMERIC
            SELECT price FROM products WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[0].type == "Decimal")
    }

    @Test func parsesNumericWithPrecisionAsDecimal() throws {
        let input = """
            -- @query GetPrice :one
            -- @param id: UUID
            -- @returns price: NUMERIC(10,2)
            SELECT price FROM products WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[0].type == "Decimal")
    }

    @Test func parsesOptionalNumericWithPrecisionAsOptionalDecimal() throws {
        let input = """
            -- @query GetPrice :one
            -- @param id: UUID
            -- @returns discount: NUMERIC(5,2)?
            SELECT discount FROM products WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[0].type == "Decimal?")
    }

    @Test func parsesDecimalTypeAsDecimal() throws {
        let input = """
            -- @query GetAmount :one
            -- @param id: UUID
            -- @returns amount: DECIMAL
            SELECT amount FROM invoices WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[0].type == "Decimal")
    }

    // MARK: Common integer alias tests

    @Test func parsesIntegerAsInt() throws {
        let input = """
            -- @query GetCount :one
            -- @param id: UUID
            -- @returns count: INTEGER
            SELECT count FROM stats WHERE id = $1;
            """
        let result = try SQLParser.parseQueryFile(input)
        #expect(result.queries[0].returns[0].type == "Int")
    }

    @Test func throwsOnMalformedParam() {
        let input = """
            -- @query GetUser :one
            -- @param id
            -- @returns id: UUID
            SELECT id FROM users WHERE id = $1;
            """
        #expect(throws: SQLParserError.malformedAnnotation("id")) {
            try SQLParser.parseQueryFile(input)
        }
    }

    @Test func throwsOnSkippedPlaceholder() {
        let input = """
            -- @query GetUser :one
            -- @param id: UUID
            -- @param name: String
            -- @param email: String
            -- @returns id: UUID
            SELECT id FROM users WHERE id = $1 AND role = $3;
            """
        #expect(throws: (any Error).self) {
            try SQLParser.parseQueryFile(input)
        }
    }

    // MARK: parseMigrationFile

    @Test func parsesMigrationFile() {
        let m = SQLParser.parseMigrationFile(
            name: "001_create_users.migration.sql",
            contents: "CREATE TABLE users (id UUID PRIMARY KEY);\n"
        )
        #expect(m.name == "001_create_users.migration.sql")
        #expect(m.sql == "CREATE TABLE users (id UUID PRIMARY KEY);")
    }
}
