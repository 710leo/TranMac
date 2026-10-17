import Foundation

/// Streams translations from an OpenAI-compatible `/chat/completions` endpoint.
struct LLMClient {
  var baseURL: String
  var apiKey: String
  var model: String

  struct Failure: LocalizedError {
    let errorDescription: String?
  }

  var isConfigured: Bool {
    endpoint != nil && !model.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private var endpoint: URL? {
    var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    while base.hasSuffix("/") { base.removeLast() }
    if !base.hasSuffix("/chat/completions") { base += "/chat/completions" }
    guard let url = URL(string: base), url.scheme?.hasPrefix("http") == true, url.host != nil else { return nil }
    return url
  }

  /// Translates `text` into `target` (an English language name), calling `onDelta` with each streamed chunk.
  @MainActor
  func translate(_ text: String, into target: String, onDelta: (String) -> Void) async throws {
    guard let endpoint, isConfigured else { throw Failure(errorDescription: "请先在设置中填写 Base URL 和模型") }

    var request = URLRequest(url: endpoint, timeoutInterval: 60)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
    let body: [String: Any] = [
      "model": model.trimmingCharacters(in: .whitespaces),
      "stream": true,
      "messages": [
        [
          "role": "system",
          "content": """
            You are a translation engine. Translate the user's text into \(target). \
            Output only the translation — no explanations, notes, or quotes. Preserve the original formatting.
            """,
        ],
        ["role": "user", "content": text],
      ],
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (bytes, response) = try await URLSession.shared.bytes(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0

    var raw = ""  // Non-SSE lines: error bodies or a non-streaming reply.
    var streamed = false
    for try await line in bytes.lines {
      guard status == 200, line.hasPrefix("data:") else {
        raw += line
        continue
      }
      let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
      if payload == "[DONE]" { break }
      guard let json = Self.object(payload) else { continue }
      if let message = Self.errorMessage(json) { throw Failure(errorDescription: message) }
      let choice = (json["choices"] as? [[String: Any]])?.first
      if let delta = (choice?["delta"] as? [String: Any])?["content"] as? String, !delta.isEmpty {
        streamed = true
        onDelta(delta)
      }
    }

    let json = Self.object(raw)
    guard status == 200 else {
      let detail = json.flatMap(Self.errorMessage) ?? String(raw.prefix(200))
      throw Failure(errorDescription: "HTTP \(status)\(detail.isEmpty ? "" : "：\(detail)")")
    }
    if !streamed {
      let choice = (json?["choices"] as? [[String: Any]])?.first
      guard let content = (choice?["message"] as? [String: Any])?["content"] as? String else {
        throw Failure(errorDescription: "无法解析返回结果")
      }
      onDelta(content)
    }
  }

  private static func object(_ string: String) -> [String: Any]? {
    guard let data = string.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  private static func errorMessage(_ json: [String: Any]) -> String? {
    if let error = json["error"] as? [String: Any] { return error["message"] as? String ?? "\(error)" }
    return json["error"] as? String
  }
}
