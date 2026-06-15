import Testing
@testable import PostgresModelsGeneratorCore

struct RuntimeCodeGeneratorTests {
    @Test func emitsProtocolAndConformances() {
        let output = RuntimeCodeGenerator.generate()
        #expect(output.contains("protocol PostgresQueryRunner: Sendable {"))
        #expect(output.contains("func query(_ query: PostgresQuery, logger: Logger, file: String, line: Int) async throws -> PostgresRowSequence"))
        #expect(output.contains("extension PostgresConnection: PostgresQueryRunner {}"))
        #expect(output.contains("extension PostgresClient: PostgresQueryRunner {"))
    }

    @Test func emitsConvenienceOverload() {
        let output = RuntimeCodeGenerator.generate()
        // The two-argument convenience overload lets generated code call
        // `db.query("…", logger: logger)` without supplying file/line.
        #expect(output.contains("func query(_ query: PostgresQuery, logger: Logger) async throws -> PostgresRowSequence"))
        #expect(output.contains("#fileID"))
    }

    @Test func clientWrapperPromotesLoggerToOptionalToAvoidRecursion() {
        let output = RuntimeCodeGenerator.generate()
        #expect(output.contains("let optionalLogger: Logger? = logger"))
        #expect(output.contains("return try await self.query(query, logger: optionalLogger, file: file, line: line)"))
    }

    @Test func emitsRequiredImports() {
        let output = RuntimeCodeGenerator.generate()
        #expect(output.contains("import Logging"))
        #expect(output.contains("import PostgresNIO"))
    }
}
