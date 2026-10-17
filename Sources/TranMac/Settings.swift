import Foundation
import Observation

enum TranslationProvider: String, CaseIterable, Identifiable {
  case system
  case llm

  var id: Self { self }

  var title: String {
    switch self {
    case .system: "系统翻译（离线）"
    case .llm: "LLM API（OpenAI 兼容）"
    }
  }
}

/// User preferences, persisted in UserDefaults.
@MainActor
@Observable
final class Settings {
  static let shared = Settings()

  var provider: TranslationProvider {
    didSet { defaults.set(provider.rawValue, forKey: "provider") }
  }
  var baseURL: String {
    didSet { defaults.set(baseURL, forKey: "llm.baseURL") }
  }
  var apiKey: String {
    didSet { defaults.set(apiKey, forKey: "llm.apiKey") }
  }
  var model: String {
    didSet { defaults.set(model, forKey: "llm.model") }
  }

  @ObservationIgnored private let defaults = UserDefaults.standard

  private init() {
    provider = defaults.string(forKey: "provider").flatMap(TranslationProvider.init) ?? .system
    baseURL = defaults.string(forKey: "llm.baseURL") ?? "https://api.openai.com/v1"
    apiKey = defaults.string(forKey: "llm.apiKey") ?? ""
    model = defaults.string(forKey: "llm.model") ?? ""
  }

  var llmClient: LLMClient {
    LLMClient(baseURL: baseURL, apiKey: apiKey, model: model)
  }
}
