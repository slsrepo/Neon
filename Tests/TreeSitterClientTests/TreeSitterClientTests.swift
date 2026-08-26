import Foundation
import Testing

import Rearrange
import SwiftTreeSitter
import TreeSitterClient
import NeonTestsTreeSitterSwift

struct TreeSitterClientTests {
	private static let swiftConfig: LanguageConfiguration = {
		let language = Language(language: tree_sitter_swift())

		let queryText = """
["func"] @keyword.function
["var" "let"] @keyword
"""

		let highlightQuery = try! Query(language: language, data: queryText.data(using: .utf8)!)

		return LanguageConfiguration(language,
									 name: "Swift",
									 queries: [.highlights: highlightQuery])
	}()

	private static let selfInjectingSwiftConfig: LanguageConfiguration = {
		let queryText = """
((line_str_text) @injection.content (#set! injection.language "swift"))
"""
		let injectionQuery = try! Query(language: swiftConfig.language, data: queryText.data(using: .utf8)!)

		var queries = swiftConfig.queries

		queries[.injections] = injectionQuery

		return LanguageConfiguration(swiftConfig.language,
									 name: swiftConfig.name,
									 queries: queries)
	}()


	@MainActor
	@Test func synchronousQuery() throws {
		let source = """
func main() {
 print("hello!")
}
"""

		let clientConfig = TreeSitterClient.Configuration(
			languageProvider: { _ in nil },
			contentSnapshopProvider: { _ in .init(string: source) },
			lengthProvider: { source.utf16.count },
			invalidationHandler: { _ in },
			locationTransformer: { _ in nil }
		)

		let client = try TreeSitterClient(
			rootLanguageConfig: Self.swiftConfig,
			configuration: clientConfig
		)

		let provider = source.predicateTextProvider

		let highlights = try client.highlights(in: NSRange(0..<24), provider: provider, mode: .required)
		let expected = [
			NamedRange(name: "keyword.function", range: NSRange(0..<4), pointRange: Point(row: 0, column: 0)..<Point(row: 0, column: 8))
		]

		#expect(highlights == expected)
	}

	@MainActor
	@Test func synchronousQueryAfterEditAffectingInjection() async throws {
		var source = """
let host = 0
"""

		let clientConfig = TreeSitterClient.Configuration(
			languageProvider: { name in
				precondition(name == "swift")

				return Self.swiftConfig
			},
			contentSnapshopProvider: { _ in .init(string: source) },
			lengthProvider: { source.utf16.count },
			invalidationHandler: { _ in },
			locationTransformer: { _ in nil }
		)

		let client = try TreeSitterClient(
			rootLanguageConfig: Self.selfInjectingSwiftConfig,
			configuration: clientConfig
		)

		let provider = source.predicateTextProvider

		let initialHighlights = try await client.highlights(in: NSRange(0..<source.utf16.count), provider: provider, mode: .required)
		let expected = [
			NamedRange(name: "keyword", range: NSRange(0..<3), pointRange: Point(row: 0, column: 0)..<Point(row: 0, column: 6))
		]

		await client.validationCompleted()

		#expect(initialHighlights == expected)
//
		client.willChangeContent(in: NSRange(11..<12))
		
		source = """
let host = "let inner = 1"
"""

		client.didChangeContent(in: NSRange(11..<12), delta: 14)

		await client.validationCompleted()

		await Task.yield()
		try! await Task.sleep(nanoseconds: 1_000_000_000)
		await Task.yield()

		let editedHighlights = try await client.highlights(in: NSRange(0..<source.utf16.count), provider: provider, mode: .required)

		#expect(editedHighlights != expected)
	}
}

//final class TreeSitterClientTests: XCTestCase {
//    func testInsertAffectedRange() {
//        let mutation = RangeMutation(range: .zero, delta: 10, limit: 10)
//        let inputEdit = InputEdit(startByte: 0,
//                                  oldEndByte: 0,
//                                  newEndByte: 20,
//                                  startPoint: Point(row: 0, column: 0),
//                                  oldEndPoint: Point(row: 0, column: 0),
//                                  newEndPoint: Point(row: 0, column: 10))
//        let edit = TreeSitterClient.ContentEdit(rangeMutation: mutation, inputEdit: inputEdit, limit: 10)
//
//        XCTAssertEqual(edit.affectedRange, NSRange(0..<10))
//    }
//
//    func testInsertClampedAffectedRange() {
//        let mutation = RangeMutation(range: .zero, delta: 10, limit: 10)
//        let inputEdit = InputEdit(startByte: 0,
//                                  oldEndByte: 0,
//                                  newEndByte: 20,
//                                  startPoint: Point(row: 0, column: 0),
//                                  oldEndPoint: Point(row: 0, column: 0),
//                                  newEndPoint: Point(row: 0, column: 10))
//        let edit = TreeSitterClient.ContentEdit(rangeMutation: mutation, inputEdit: inputEdit, limit: 5)
//
//        XCTAssertEqual(edit.affectedRange, NSRange(0..<5))
//    }
//
//    func testDeleteAffectedRange() {
//        let mutation = RangeMutation(range: NSRange(0..<10), delta: -10)
//        let inputEdit = InputEdit(startByte: 0,
//                                  oldEndByte: 20,
//                                  newEndByte: 0,
//                                  startPoint: Point(row: 0, column: 0),
//                                  oldEndPoint: Point(row: 0, column: 10),
//                                  newEndPoint: Point(row: 0, column: 0))
//        let edit = TreeSitterClient.ContentEdit(rangeMutation: mutation, inputEdit: inputEdit, limit: 0)
//
//        XCTAssertEqual(edit.affectedRange, NSRange(0..<0))
//    }
//
//	func testAffectedRangeWithInsertAtEnd() {
//		let mutation = RangeMutation(range: NSRange(0..<10), delta: -10)
//		let inputEdit = InputEdit(startByte: 0,
//								  oldEndByte: 20,
//								  newEndByte: 0,
//								  startPoint: Point(row: 0, column: 0),
//								  oldEndPoint: Point(row: 0, column: 10),
//								  newEndPoint: Point(row: 0, column: 0))
//		let edit = TreeSitterClient.ContentEdit(rangeMutation: mutation, inputEdit: inputEdit, limit: 0)
//
//		XCTAssertEqual(edit.affectedRange, NSRange(0..<0))
//	}
//}
//
//extension TreeSitterClientTests {
//
//	func testRegularQuery() async throws {
//		let language = Language(language: tree_sitter_swift())
//
//		let client = try TreeSitterClient(language: language)
//
//let content = """
//func main() { print("hello" }
//"""
//
//		await MainActor.run {
//			client.didChangeContent(to: content, in: .zero, delta: content.utf16.count, limit: content.utf16.count)
//		}
//
//		let queryText = """
//("func" @keyword.function)
//"""
//		let queryData = try XCTUnwrap(queryText.data(using: .utf8))
//		let query = try Query(language: language, data: queryData)
//
//		let highlights = try await client.highlights(with: query, in: NSRange(0..<4))
//
//		let range = NamedRange(nameComponents: ["keyword", "function"],
//							   tsRange: TSRange(points: Point(row: 0, column: 0)..<Point(row: 0, column: 8),
//												bytes: 0..<8))
//		XCTAssertEqual(highlights, [range])
//	}
//
//	func testStaleQuery() throws {
//		let language = Language(language: tree_sitter_swift())
//
//		let client = try TreeSitterClient(language: language, synchronousLengthThreshold: 1)
//
//let content = """
//func main() { print("hello" }
//"""
//
//		let queryText = """
//("func" @keyword.function)
//"""
//		let queryData = try XCTUnwrap(queryText.data(using: .utf8))
//		let query = try Query(language: language, data: queryData)
//
//		var result: Result<[NamedRange], TreeSitterClientError> = .failure(.stateInvalid)
//
//		let queryExpectation = expectation(description: "query")
//
//		// the goal here is to begin the query, and then submit a change so
//		// the query runs on stale content. It's slightly hard to control all of the execution
//		// here, but I'm fairly sure this will work without races.
//		client.executeHighlightsQuery(query, in: NSRange(0..<4)) { queryResult in
//			result = queryResult
//			queryExpectation.fulfill()
//		}
//
//		client.didChangeContent(to: content, in: .zero, delta: content.utf16.count, limit: content.utf16.count)
//
//		wait(for: [queryExpectation], timeout: 2.0)
//
//		switch result {
//		case .failure(.staleContent):
//			break
//		default:
//			XCTFail("Should have failed: \(result)")
//		}
//	}
//}

