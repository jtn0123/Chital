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

class OllamaService {
    @AppStorage("ollamaBaseURL") private var baseURLString = AppConstants.ollamaDefaultBaseURL
    @AppStorage("contextWindowLength") private var contextWindowLength = AppConstants.contextWindowLength
    
    private let session: NetworkSession // Use the protocol type
    
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
    
    func sendSingleMessage(model: String, messages: [OllamaChatMessage]) async throws -> String {
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
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = baseURL.appendingPathComponent("chat")
                    let payload = OllamaChatRequest(model: model, messages: messages, stream: true, options: OllamaChatRequestOptions(num_ctx: contextWindowLength))
                    
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONEncoder().encode(payload)
                    
                    // Use the injected session
                    let (stream, _) = try await session.bytes(for: req)
                    
                    for try await line in stream.lines {
                        try Task.checkCancellation()
                        if let data = line.data(using: .utf8),
                           let res = try? JSONDecoder().decode(OllamaChatResponse.self, from: data) {
                            if let content = res.message?.content {
                                continuation.yield(content)
                            }
                            if res.done {
                                continuation.finish()
                                return
                            }
                        }
                    }
                    // Handle cases where the loop finishes without a 'done' message if necessary
                    continuation.finish() 
                } catch {
                    continuation.finish(throwing: error)
                }
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
