import SwiftUI

struct SettingsView: View {
  @Bindable var settings: Settings

  @State private var testing = false
  @State private var testResult: String?

  var body: some View {
    Form {
      Picker("翻译服务", selection: $settings.provider) {
        ForEach(TranslationProvider.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.radioGroup)

      Section {
        TextField("Base URL", text: $settings.baseURL, prompt: Text("https://api.openai.com/v1"))
        SecureField("API Key", text: $settings.apiKey, prompt: Text("本地模型可留空"))
        TextField("模型", text: $settings.model, prompt: Text("例如 gpt-4o-mini、deepseek-chat"))
        HStack {
          Button("测试连接", action: test).disabled(testing)
          if testing { ProgressView().controlSize(.small) }
          if let testResult {
            Text(testResult).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
          }
        }
      } header: {
        Text("LLM API")
      } footer: {
        Text("支持任意 OpenAI 兼容的 /chat/completions 接口，如 OpenAI、DeepSeek、通义千问、OpenRouter、Ollama 等。")
          .foregroundStyle(.secondary)
      }
      .disabled(settings.provider != .llm)
    }
    .formStyle(.grouped)
    .frame(width: 480)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func test() {
    testing = true
    testResult = nil
    Task {
      var output = ""
      do {
        try await settings.llmClient.translate("Hello, world!", into: "Simplified Chinese") { output += $0 }
        testResult = "✓ \(output)"
      } catch {
        testResult = "✗ \(error.localizedDescription)"
      }
      testing = false
    }
  }
}
