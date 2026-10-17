import Foundation
import NaturalLanguage
import Observation
import Translation

@MainActor
@Observable
final class Translator {
  var input = "" {
    didSet { if input != oldValue { schedule() } }
  }
  var output = ""
  var direction = ""
  var message: String?
  /// Language pair whose pack is missing; the UI offers to download it.
  var missingPair: (source: Locale.Language, target: Locale.Language)?
  /// Setting this triggers the system download sheet via `.translationTask`.
  var downloadConfig: TranslationSession.Configuration?

  private let settings = Settings.shared
  private var task: Task<Void, Never>?
  private var sessions: [String: TranslationSession] = [:]

  private static let chinese = Locale.Language(identifier: "zh-Hans")
  private static let english = Locale.Language(identifier: "en")

  func reset() {
    task?.cancel()
    input = ""
    output = ""
    direction = ""
    message = nil
    missingPair = nil
  }

  private func schedule() {
    task?.cancel()
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      output = ""
      direction = ""
      message = nil
      missingPair = nil
      return
    }
    // LLM requests cost money, so wait for a longer typing pause.
    let delay = settings.provider == .llm ? 400 : 80
    task = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(delay))
      guard !Task.isCancelled else { return }
      await self?.translate(text)
    }
  }

  func retry() {
    sessions.removeAll()
    schedule()
  }

  private func translate(_ text: String) async {
    let (source, target) = Self.languages(for: text)
    direction = "\(Self.label(source)) → \(Self.label(target))"
    switch settings.provider {
    case .system:
      await translateWithSystem(text, from: source, to: target)
    case .llm:
      direction += " · LLM"
      await translateWithLLM(text, to: target)
    }
  }

  private func translateWithLLM(_ text: String, to target: Locale.Language) async {
    missingPair = nil
    if output.isEmpty { message = "翻译中…" }
    var started = false
    do {
      try await settings.llmClient.translate(text, into: Self.englishName(target)) { delta in
        guard !Task.isCancelled else { return }
        if !started {
          started = true
          output = ""
          message = nil
        }
        output += delta
      }
      guard !Task.isCancelled else { return }
      if !started {
        output = ""
        message = nil
      }
    } catch {
      guard !Task.isCancelled else { return }
      if !started { output = "" }
      message = "翻译失败：\(error.localizedDescription)"
    }
  }

  private func translateWithSystem(_ text: String, from source: Locale.Language, to target: Locale.Language) async {
    let status = await LanguageAvailability().status(from: source, to: target)
    guard !Task.isCancelled else { return }
    switch status {
    case .installed:
      break
    case .supported:
      output = ""
      message = "需要先下载 \(Self.label(source)) / \(Self.label(target)) 离线语言包"
      missingPair = (source, target)
      return
    default:
      output = ""
      message = "系统不支持该语言方向"
      missingPair = nil
      return
    }

    let key = "\(source.maximalIdentifier)->\(target.maximalIdentifier)"
    let session = sessions[key] ?? TranslationSession(installedSource: source, target: target)
    sessions[key] = session
    do {
      let response = try await session.translate(text)
      guard !Task.isCancelled else { return }
      output = response.targetText
      message = nil
      missingPair = nil
    } catch {
      guard !Task.isCancelled else { return }
      sessions[key] = nil
      output = ""
      message = "翻译失败：\(error.localizedDescription)"
    }
  }

  func requestDownload() {
    guard let pair = missingPair else { return }
    downloadConfig = TranslationSession.Configuration(source: pair.source, target: pair.target)
  }

  func downloadFinished() {
    downloadConfig = nil
    retry()
  }

  /// Chinese input → English; anything else → Simplified Chinese.
  static func languages(for text: String) -> (Locale.Language, Locale.Language) {
    if text.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }) {
      return (chinese, english)
    }
    let recognizer = NLLanguageRecognizer()
    recognizer.languageHints = [.english: 0.9]
    recognizer.processString(text)
    guard let lang = recognizer.dominantLanguage, lang != .undetermined, !lang.rawValue.hasPrefix("zh") else {
      return (english, chinese)
    }
    return (Locale.Language(identifier: lang.rawValue), chinese)
  }

  static func englishName(_ lang: Locale.Language) -> String {
    if lang == chinese { return "Simplified Chinese" }
    let code = lang.languageCode?.identifier ?? lang.minimalIdentifier
    return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
  }

  static func label(_ lang: Locale.Language) -> String {
    let code = lang.languageCode?.identifier ?? lang.minimalIdentifier
    return Locale(identifier: "zh-Hans").localizedString(forLanguageCode: code) ?? code
  }
}
