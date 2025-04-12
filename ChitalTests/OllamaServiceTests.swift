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
    static func makeAsyncBytes(from strings: [String], url: URL, statusCode: Int = 200) -> (URLSession.AsyncBytes, URLResponse) {
        let stringData = strings.joined(separator: "\n").data(using: .utf8)!
        let byteStream = URLSession.shared.bytes(for: URLRequest(url: URL(string: "data:application/octet-stream;base64,\(stringData.base64EncodedString())")!))
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
        // You could add more assertions here to check the request body if needed
        // E.g., decode mockSession.lastRequest?.httpBody and check its contents
    }

    // --- TODO: Add tests for: ---
    // 1. sendSingleMessage failure (network error, decoding error)
    // 2. streamConversation success (multiple chunks, correct order, finish on 'done')
    // 3. streamConversation failure (network error during stream)
    // 4. Check request body contents (model, messages, stream flag, options)

    // We might add performance tests later if needed.
    // func testPerformanceExample() throws {
    //     // This is an example of a performance test case.
    //     self.measure {
    //         // Put the code you want to measure the time of here.
    //     }
    // }

} 