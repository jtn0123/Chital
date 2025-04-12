import Foundation
import SwiftUI

// --- Protocol for Network Session ---
protocol NetworkSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse)
}

// --- Make URLSession conform ---
extension URLSession: NetworkSession {
    // Provide implementations that call the original URLSession methods
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        // Explicitly call the instance method on self (which is the URLSession instance)
        return try await self.data(for: request, delegate: nil)
    }
    
    func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        // Explicitly call the instance method on self (which is the URLSession instance)
        return try await self.bytes(for: request, delegate: nil)
    }
}
// --- Protocol End ---

struct OllamaChatMessage: Codable {
    let role: String
    let content: String
}

struct OllamaChatRequestOptions: Codable {
    let num_ctx: Int
}

struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OllamaChatMessage]
    let stream: Bool?
    let options: OllamaChatRequestOptions?
}

struct OllamaChatResponse: Codable {
    let message: OllamaChatMessage?
    let done: Bool
}

struct OllamaModelResponse: Codable {
    let models: [OllamaModel]
}

struct OllamaModel: Codable {
    let name: String
}

// Make OllamaService conform to ObservableObject
class OllamaService: ObservableObject {
    // If you later add properties here that the UI should react to,
    // mark them with @Published, e.g.:
    // @Published var someStateVariable: Bool = false
    
    @AppStorage("ollamaBaseURL") private var baseURLString = AppConstants.ollamaDefaultBaseURL
    @AppStorage("contextWindowLength") private var contextWindowLength = AppConstants.contextWindowLength
    
    private let session: NetworkSession // Use the protocol type
    private var currentStreamingTask: Task<Void, Never>? // Store the non-throwing streaming task
    
    private var baseURL: URL {
        guard let url = URL(string: baseURLString) else {
            fatalError("Invalid base URL: \(baseURLString)")
        }
        return url
    }
    
    // --- Initializers ---
    // Default initializer for the app
    init(session: NetworkSession = URLSession.shared) {
        self.session = session
    }
    // --- Initializers End ---
    
    // Method to cancel the current stream
    func cancelStream() {
        currentStreamingTask?.cancel()
        currentStreamingTask = nil
        print("OllamaService: Stream cancelled.")
    }
    
    func sendSingleMessage(model: String, messages: [OllamaChatMessage]) async throws -> String {
        // Ensure sending a single message cancels any ongoing stream
        await Task { cancelStream() }.value
        
        let url = baseURL.appendingPathComponent("chat")
        let payload = OllamaChatRequest(model: model, messages: messages, stream: false, options: OllamaChatRequestOptions(num_ctx: contextWindowLength))
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(payload)
        
        // Use the injected session
        let (data, _) = try await session.data(for: req)
        let res = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        
        return res.message?.content ?? ""
    }
    
    func streamConversation(model: String, messages: [OllamaChatMessage]) -> AsyncThrowingStream<String, Error> {
        // Cancel any existing stream task before starting a new one
        cancelStream()
        
        return AsyncThrowingStream { continuation in
            // Create and store the task
            let task = Task {
                defer {
                    // Ensure task reference is cleared when the task finishes
                    self.currentStreamingTask = nil
                    print("OllamaService: Stream task finished.")
                }
                do {
                    let url = baseURL.appendingPathComponent("chat")
                    let payload = OllamaChatRequest(model: model, messages: messages, stream: true, options: OllamaChatRequestOptions(num_ctx: contextWindowLength))
                    
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONEncoder().encode(payload)
                    
                    print("OllamaService: Starting stream request...")
                    // Use the injected session
                    let (stream, _) = try await session.bytes(for: req)
                    print("OllamaService: Stream connection established.")
                    
                    for try await line in stream.lines {
                        // Check for cancellation *before* processing the line
                        try Task.checkCancellation()
                        print("OllamaService: Received stream line.")
                        if let data = line.data(using: .utf8),
                           let res = try? JSONDecoder().decode(OllamaChatResponse.self, from: data) {
                            if let content = res.message?.content {
                                print("OllamaService: Yielding content.")
                                continuation.yield(content)
                            }
                            if res.done {
                                print("OllamaService: Done message received.")
                                continuation.finish()
                                return // Exit the task successfully
                            }
                        }
                    }
                    // Handle cases where the loop finishes without a 'done' message if necessary
                    print("OllamaService: Stream finished without done message.")
                    continuation.finish() 
                } catch is CancellationError {
                    // Handle cancellation gracefully
                    print("OllamaService: Stream task cancelled.")
                    continuation.finish(throwing: CancellationError())
                } catch {
                    // Handle other errors
                    print("OllamaService: Stream task failed with error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
            // Store the reference to the task
            self.currentStreamingTask = task
            
            // Handle continuation termination (optional but good practice)
            continuation.onTermination = { @Sendable _ in
                print("OllamaService: Stream continuation terminated.")
                task.cancel() // Cancel the task if the stream consumer terminates early
            }
        }
    }
    
    func fetchModelList() async throws -> [String] {
        let url = baseURL.appendingPathComponent("tags")
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        
        // Use the injected session
        let (data, _) = try await session.data(for: req)
        let res = try JSONDecoder().decode(OllamaModelResponse.self, from: data)
        
        return res.models.map { $0.name }
    }
}
