import SwiftUI

// MARK: - Rasyon AI Asistanı sohbet ekranı

struct RationAssistantSheet: View {
    let vm: FormulaEditorVM

    @Environment(\.dismiss) private var dismiss

    @State private var assistant   = RationAssistant()
    @State private var availability = RationAssistant.checkAvailability()
    @State private var messages:   [ChatMessage] = []
    @State private var input       = ""
    @State private var isThinking  = false
    @State private var didStart    = false

    struct ChatMessage: Identifiable {
        let id = UUID()
        let isUser: Bool
        var text: String
    }

    var body: some View {
        NavigationStack {
            Group {
                if availability == .available {
                    chatView
                } else {
                    unavailableView
                }
            }
            .navigationTitle("Rasyon Asistanı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .onAppear {
                guard !didStart, availability == .available else { return }
                didStart = true
                let context = RationContextBuilder.build(vm: vm)
                assistant.startSession(context: context)
                messages.append(ChatMessage(
                    isUser: false,
                    text: "Merhaba! \"\(vm.name.isEmpty ? "Bu" : vm.name)\" formülün hakkında sorularını yanıtlayabilirim. "
                        + "Örneğin: \"Bu rasyonu nasıl ucuzlatırım?\" veya \"Proteini artırmak için ne yapmalıyım?\""
                ))
            }
        }
    }

    // MARK: - Sohbet

    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { msg in
                            messageBubble(msg).id(msg.id)
                        }
                        if isThinking, messages.last?.isUser == true {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text("Düşünüyor…").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .id("thinking")
                        }
                    }
                    .padding(12)
                }
                .onChange(of: messages.last?.text) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
            }

            Divider()
            inputBar
        }
    }

    private func messageBubble(_ msg: ChatMessage) -> some View {
        HStack {
            if msg.isUser { Spacer(minLength: 40) }
            Text(msg.text.isEmpty ? " " : msg.text)
                .font(.subheadline)
                .foregroundStyle(msg.isUser ? .white : .primary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(
                    msg.isUser ? AnyShapeStyle(Color.accentColor)
                               : AnyShapeStyle(Color(.secondarySystemBackground)),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .textSelection(.enabled)
            if !msg.isUser { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Sorunu yaz…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: Capsule())

            Button { Task { await send() } } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespaces).isEmpty && !isThinking
    }

    private func send() async {
        let question = input.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty else { return }
        input = ""
        messages.append(ChatMessage(isUser: true, text: question))
        isThinking = true

        // Asistan cevabı için boş balon ekle, streaming ile doldur
        let replyID = UUID()
        var replyIndex: Int?

        do {
            _ = try await assistant.send(question) { partial in
                if let idx = replyIndex {
                    messages[idx].text = partial
                } else {
                    messages.append(ChatMessage(isUser: false, text: partial))
                    replyIndex = messages.count - 1
                }
            }
            _ = replyID
        } catch {
            let msg = "⚠️ \(error.localizedDescription)"
            if let idx = replyIndex {
                messages[idx].text = msg
            } else {
                messages.append(ChatMessage(isUser: false, text: msg))
            }
        }
        isThinking = false
    }

    // MARK: - Kullanılamaz durumu

    private var unavailableView: some View {
        ContentUnavailableView {
            Label("Asistan Kullanılamıyor", systemImage: "sparkles.slash")
        } description: {
            Text(availability.userMessage)
        }
    }
}
