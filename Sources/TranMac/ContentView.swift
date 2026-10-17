import SwiftUI
import Translation

struct ContentView: View {
  @Bindable var model: Translator
  /// Bumped every time the panel is shown, to refocus the text field.
  let showToken: Int
  let onSubmit: () -> Void
  let onCancel: () -> Void

  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "character.bubble")
          .font(.system(size: 20))
          .foregroundStyle(.secondary)
        TextField("输入要翻译的文字…", text: $model.input)
          .textFieldStyle(.plain)
          .font(.system(size: 22))
          .focused($focused)
          .autocorrectionDisabled()
          .onSubmit(onSubmit)
          .onKeyPress(.escape) {
            onCancel()
            return .handled
          }
        if !model.direction.isEmpty {
          Text(model.direction)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
        }
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 16)

      if !model.output.isEmpty || model.message != nil {
        Divider()
        VStack(alignment: .leading, spacing: 10) {
          if !model.output.isEmpty {
            Text(model.output)
              .font(.system(size: 20))
              .textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
          }
          if let message = model.message {
            HStack {
              Text(message).foregroundStyle(.secondary)
              if model.missingPair != nil {
                Button("下载语言包") {
                  NSApp.activate()
                  model.requestDownload()
                }
              }
            }
          }
          if !model.output.isEmpty {
            Text("↩ 复制并关闭    ⎋ 关闭")
              .font(.system(size: 11))
              .foregroundStyle(.tertiary)
          }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(width: 640)
    .background(.regularMaterial)
    .translationTask(model.downloadConfig) { session in
      do {
        try await session.prepareTranslation()
      } catch {
        model.message = "下载失败：\(error.localizedDescription)"
      }
      model.downloadFinished()
    }
    .onAppear { focused = true }
    .onChange(of: showToken) { focused = true }
  }
}
