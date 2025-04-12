import XCTest
@testable import Chital // Import the main app module to access its code

// MARK: - Mock Network Session

// Define a simple error for testing purposes
enum MockNetworkError: Error {
    case mockError
}

// Define a structure to hold mock data/errors for a specific request
struct MockResponse {
    var data: Data?
    var asyncBytes: URLSession.AsyncBytes?
    var response: URLResponse?
    var error: Error?
}

class MockNetworkSession: NetworkSession {
    // Dictionary to store predefined responses based on URL
    var mockResponses: [URL: MockResponse] = [:]
    
    // Keep track of the last request made for verification
    private(set) var lastRequest: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        guard let url = request.url, let mock = mockResponses[url] else {
            throw MockNetworkError.mockError // Or a more specific error like "No mock found"
        }
        
        if let error = mock.error {
            throw error
        }
        
        guard let data = mock.data, let response = mock.response else {
             throw MockNetworkError.mockError // Or "Mock data/response missing"
        }
        
        return (data, response)
    }

    func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        lastRequest = request
        guard let url = request.url, let mock = mockResponses[url] else {
            throw MockNetworkError.mockError // Or a more specific error like "No mock found"
        }
        
        if let error = mock.error {
            throw error
        }
        
        guard let bytes = mock.asyncBytes, let response = mock.response else {
             throw MockNetworkError.mockError // Or "Mock bytes/response missing"
        }
        
        return (bytes, response)
    }
    
    // Helper to easily create AsyncBytes from strings for streaming tests
    static func makeAsyncBytes(from strings: [String], url: URL, statusCode: Int = 200) async throws -> (URLSession.AsyncBytes, URLResponse) {
        let stringData = strings.joined(separator: "\n").data(using: .utf8)!
        let byteStream = try await URLSession.shared.bytes(for: URLRequest(url: URL(string: "data:application/octet-stream;base64,\(stringData.base64EncodedString())")!))
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (byteStream.0, response)
    }
}

// MARK: - Test Class

final class OllamaServiceTests: XCTestCase {

    var mockSession: MockNetworkSession!
    var ollamaService: OllamaService!

    override func setUpWithError() throws {
        try super.setUpWithError() // Call super
        // Create a new mock session and service for each test
        mockSession = MockNetworkSession()
        ollamaService = OllamaService(session: mockSession)
        
        // You might need to override AppStorage defaults here for consistent testing
        // UserDefaults.standard.set("http://localhost:11434/api", forKey: "ollamaBaseURL")
        // UserDefaults.standard.set(2048, forKey: "contextWindowLength")
    }

    override func tearDownWithError() throws {
        // Clean up
        mockSession = nil
        ollamaService = nil
        // Reset UserDefaults if you overrode them in setUp
        // UserDefaults.standard.removeObject(forKey: "ollamaBaseURL")
        // UserDefaults.standard.removeObject(forKey: "contextWindowLength")
        try super.tearDownWithError() // Call super
    }

    // Helper to construct the expected URL for mocking
    private func expectedURL(path: String) -> URL {
        // Use the default base URL for consistency in tests, or read from UserDefaults if overridden
        let baseUrlString = UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? AppConstants.ollamaDefaultBaseURL
        return URL(string: baseUrlString)!.appendingPathComponent(path)
    }

    // MARK: - Tests

    func testFetchModelList_Success() async throws {
        // Arrange
        let expectedModels = ["llama3:latest", "codellama:latest"]
        let mockResponseData = OllamaModelResponse(models: expectedModels.map { OllamaModel(name: $0) })
        let jsonData = try JSONEncoder().encode(mockResponseData)
        let url = expectedURL(path: "tags")
        let urlResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        
        mockSession.mockResponses[url] = MockResponse(data: jsonData, response: urlResponse)
        
        // Act
        let models = try await ollamaService.fetchModelList()
        
        // Assert
        XCTAssertEqual(models, expectedModels, "Fetched models should match the expected list.")
        XCTAssertEqual(mockSession.lastRequest?.url, url, "Request URL should match.")
        XCTAssertEqual(mockSession.lastRequest?.httpMethod, "GET", "HTTP method should be GET.")
    }

    func testFetchModelList_Failure_NetworkError() async throws {
        // Arrange
        let url = expectedURL(path: "tags")
        let expectedError = MockNetworkError.mockError
        mockSession.mockResponses[url] = MockResponse(error: expectedError)
        
        // Act & Assert
        do {
            _ = try await ollamaService.fetchModelList()
            XCTFail("Expected fetchModelList to throw an error, but it did not.")
        } catch let error as MockNetworkError {
            XCTAssertEqual(error, expectedError, "Caught error should be the mock network error.")
        } catch {
            XCTFail("Caught unexpected error type: \(error)")
        }
        XCTAssertEqual(mockSession.lastRequest?.url, url, "Request URL should match.")
    }
    
    func testSendSingleMessage_Success() async throws {
        // Arrange
        let model = "test-model"
        let messages = [OllamaChatMessage(role: "user", content: "Hello")]
        let expectedContextLength = UserDefaults.standard.integer(forKey: "contextWindowLength") == 0 ? AppConstants.contextWindowLength : UserDefaults.standard.integer(forKey: "contextWindowLength") // Handle default
        let expectedResponseContent = "Hi there!"
        let mockResponsePayload = OllamaChatResponse(message: OllamaChatMessage(role: "assistant", content: expectedResponseContent), done: true)
        let jsonData = try JSONEncoder().encode(mockResponsePayload)
        let url = expectedURL(path: "chat")
        let urlResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        
        mockSession.mockResponses[url] = MockResponse(data: jsonData, response: urlResponse)
        
        // Act
        let responseContent = try await ollamaService.sendSingleMessage(model: model, messages: messages)
        
        // Assert
        XCTAssertEqual(responseContent, expectedResponseContent, "Response content should match.")
        XCTAssertEqual(mockSession.lastRequest?.url, url, "Request URL should match.")
        XCTAssertEqual(mockSession.lastRequest?.httpMethod, "POST", "HTTP method should be POST.")
        
        // Assert Request Body
        guard let requestBody = mockSession.lastRequest?.httpBody else {
            XCTFail("Request body should not be nil.")
            return
        }
        let decoder = JSONDecoder()
        let sentRequest = try decoder.decode(OllamaChatRequest.self, from: requestBody)
        XCTAssertEqual(sentRequest.model, model, "Request body model should match.")
        XCTAssertEqual(sentRequest.messages.count, messages.count, "Request body message count should match.")
        if sentRequest.messages.count == messages.count { // Avoid crash if counts differ
            for i in 0..<messages.count {
                XCTAssertEqual(sentRequest.messages[i].role, messages[i].role, "Request message role [\(i)] should match.")
                XCTAssertEqual(sentRequest.messages[i].content, messages[i].content, "Request message content [\(i)] should match.")
            }
        }
        XCTAssertEqual(sentRequest.stream, false, "Request body stream flag should be false.")
        XCTAssertEqual(sentRequest.options?.num_ctx, expectedContextLength, "Request body options.num_ctx should match.")
    }

    func testSendSingleMessage_Failure_NetworkError() async throws {
        // Arrange
        let model = "test-model"
        let messages = [OllamaChatMessage(role: "user", content: "Hello")]
        let url = expectedURL(path: "chat")
        let expectedError = MockNetworkError.mockError
        mockSession.mockResponses[url] = MockResponse(error: expectedError)
        
        // Act & Assert
        do {
            _ = try await ollamaService.sendSingleMessage(model: model, messages: messages)
            XCTFail("Expected sendSingleMessage to throw an error, but it did not.")
        } catch let error as MockNetworkError {
            XCTAssertEqual(error, expectedError, "Caught error should be the mock network error.")
        } catch {
            XCTFail("Caught unexpected error type: \(error)")
        }
        XCTAssertEqual(mockSession.lastRequest?.url, url, "Request URL should match.")
    }

    func testSendSingleMessage_Failure_DecodingError() async throws {
        // Arrange
        let model = "test-model"
        let messages = [OllamaChatMessage(role: "user", content: "Hello")]
        let invalidJsonData = "{\"invalid_structure\": true}".data(using: .utf8)!
        let url = expectedURL(path: "chat")
        let urlResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        
        mockSession.mockResponses[url] = MockResponse(data: invalidJsonData, response: urlResponse)
        
        // Act & Assert
        do {
            _ = try await ollamaService.sendSingleMessage(model: model, messages: messages)
            XCTFail("Expected sendSingleMessage to throw a decoding error, but it did not.")
        } catch is DecodingError {
            // Success - Caught the expected error type
        } catch {
            XCTFail("Caught unexpected error type: \(error)")
        }
        XCTAssertEqual(mockSession.lastRequest?.url, url, "Request URL should match.")
    }

    func testStreamConversation_Success() async throws {
        // Arrange
        let model = "test-stream-model"
        let messages = [OllamaChatMessage(role: "user", content: "Stream test")]
        let expectedContextLength = UserDefaults.standard.integer(forKey: "contextWindowLength") == 0 ? AppConstants.contextWindowLength : UserDefaults.standard.integer(forKey: "contextWindowLength") // Handle default
        let expectedContents = ["This", " is", " a", " stream."]
        let url = expectedURL(path: "chat")
        
        // Create mock stream data (each line is a JSON object)
        let streamJsonLines: [String] = [
            "{\"message\":{\"role\":\"assistant\",\"content\":\"This\"},\"done\":false}",
            "{\"message\":{\"role\":\"assistant\",\"content\":\" is\"},\"done\":false}",
            "{\"message\":{\"role\":\"assistant\",\"content\":\" a\"},\"done\":false}",
            "{\"message\":{\"role\":\"assistant\",\"content\":\" stream.\"},\"done\":false}",
            "{\"message\":null,\"done\":true}" // Final message indicates done
        ]
        
        // Use the helper to create mock AsyncBytes and URLResponse
        let (asyncBytes, urlResponse) = try await MockNetworkSession.makeAsyncBytes(from: streamJsonLines, url: url)
        
        // Configure the mock session
        mockSession.mockResponses[url] = MockResponse(asyncBytes: asyncBytes, response: urlResponse)
        
        // Act
        let stream = ollamaService.streamConversation(model: model, messages: messages)
        var receivedContents: [String] = []
        var receivedError: Error? = nil
        
        do {
            for try await contentChunk in stream {
                receivedContents.append(contentChunk)
            }
        } catch {
            receivedError = error
        }
        
        // Assert
        XCTAssertNil(receivedError, "Stream should finish without error.")
        XCTAssertEqual(receivedContents, expectedContents, "Received stream contents should match expected order and content.")
        XCTAssertEqual(mockSession.lastRequest?.url, url, "Request URL should match.")
        XCTAssertEqual(mockSession.lastRequest?.httpMethod, "POST", "HTTP method should be POST.")
        
        // Assert Request Body
        guard let requestBody = mockSession.lastRequest?.httpBody else {
            XCTFail("Request body should not be nil.")
            return
        }
        let decoder = JSONDecoder()
        let sentRequest = try decoder.decode(OllamaChatRequest.self, from: requestBody)
        XCTAssertEqual(sentRequest.model, model, "Request body model should match.")
        XCTAssertEqual(sentRequest.messages.count, messages.count, "Request body message count should match.")
        if sentRequest.messages.count == messages.count { // Avoid crash if counts differ
             for i in 0..<messages.count {
                 XCTAssertEqual(sentRequest.messages[i].role, messages[i].role, "Request message role [\(i)] should match.")
                 XCTAssertEqual(sentRequest.messages[i].content, messages[i].content, "Request message content [\(i)] should match.")
             }
         }
        XCTAssertEqual(sentRequest.stream, true, "Request body stream flag should be true.")
        XCTAssertEqual(sentRequest.options?.num_ctx, expectedContextLength, "Request body options.num_ctx should match.")
    }

    func testStreamConversation_Failure_NetworkError() async throws {
        // Arrange
        let model = "test-stream-model"
        let messages = [OllamaChatMessage(role: "user", content: "Stream failure test")]
        let url = expectedURL(path: "chat")
        let expectedError = MockNetworkError.mockError
        
        // Configure the mock session to throw an error when bytes(for:) is called
        mockSession.mockResponses[url] = MockResponse(error: expectedError)
        
        // Act
        let stream = ollamaService.streamConversation(model: model, messages: messages)
        var receivedContents: [String] = []
        var receivedError: Error? = nil
        
        do {
            // Attempt to iterate through the stream
            for try await contentChunk in stream {
                receivedContents.append(contentChunk)
            }
            // If the loop completes without throwing, the test failed
            XCTFail("Expected streamConversation to throw an error, but it completed successfully.")
        } catch let error as MockNetworkError {
            // Assert: Check if the caught error is the expected mock error
            XCTAssertEqual(error, expectedError, "Caught error should be the mock network error.")
        } catch {
            // Assert: Fail if an unexpected error type was caught
            XCTFail("Caught unexpected error type: \(error)")
        }
        
        // Assert: Check that no content was received before the error
        XCTAssertTrue(receivedContents.isEmpty, "No content should have been received before the error was thrown.")
        XCTAssertEqual(mockSession.lastRequest?.url, url, "Request URL should match.")
        XCTAssertEqual(mockSession.lastRequest?.httpMethod, "POST", "HTTP method should be POST.")
    }

    // --- TODO: Add tests for: ---
    // 1. sendSingleMessage failure (network error, decoding error) -> DONE
    // 2. streamConversation success (multiple chunks, correct order, finish on 'done') -> ADDED
    // 3. streamConversation failure (network error during stream) -> ADDED
    // 4. Check request body contents (model, messages, stream flag, options) -> ADDED

    // We might add performance tests later if needed.
    // func testPerformanceExample() throws {
    //     // This is an example of a performance test case.
    //     self.measure {
    //         // Put the code you want to measure the time of here.
    //     }
    // }

} 