import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Asistan kullanılabilirlik durumu

enum AssistantAvailability: Equatable {
    case available
    case deviceNotEligible           // Cihaz Apple Intelligence desteklemiyor
    case appleIntelligenceNotEnabled // Ayarlar'dan açılmamış
    case modelNotReady               // Model indiriliyor / hazır değil
    case sdkUnavailable              // FoundationModels bu derlemede yok

    var userMessage: String {
        switch self {
        case .available:
            return ""
        case .deviceNotEligible:
            return "Bu cihaz yapay zekâ asistanını desteklemiyor. Apple Intelligence yalnızca iPhone 15 Pro ve sonrası ile çalışır."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence kapalı. Ayarlar → Apple Intelligence & Siri bölümünden etkinleştirin."
        case .modelNotReady:
            return "Yapay zekâ modeli henüz hazır değil (indiriliyor olabilir). Lütfen biraz sonra tekrar deneyin."
        case .sdkUnavailable:
            return "Yapay zekâ asistanı bu sürümde kullanılamıyor."
        }
    }
}

// MARK: - Kullanıcıya gösterilecek asistan hatası

struct AssistantError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Rasyon AI asistanı (FoundationModels sarmalayıcı)

@MainActor
final class RationAssistant {

    static func checkAvailability() -> AssistantAvailability {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:           return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
            case .modelNotReady:               return .modelNotReady
            @unknown default:                  return .modelNotReady
            }
        @unknown default:
            return .modelNotReady
        }
        #else
        return .sdkUnavailable
        #endif
    }

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?
    #endif
    private var instructions: String = ""

    /// Formül bağlamıyla yeni bir oturum başlatır.
    func startSession(context: String) {
        instructions = RationContextBuilder.systemInstructions
            + "\n\n# GÜNCEL FORMÜL DURUMU\n" + context
        #if canImport(FoundationModels)
        session = makeSession()
        session?.prewarm()   // ilk yanıt gecikmesini ve "hazır değil" hatasını azaltır
        #endif
    }

    #if canImport(FoundationModels)
    // Yem/rasyon içeriği zararsız olduğundan daha esnek guardrail kullanılır —
    // varsayılan güvenlik filtresi bu tür teknik içerikte yanlış tetiklenebiliyor.
    private func makeSession() -> LanguageModelSession {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        return LanguageModelSession(model: model, instructions: instructions)
    }

    private func rebuildSession() {
        // Bağlam penceresi dolduğunda geçmişi sıfırlayıp aynı talimatla yeniden başlat
        session = makeSession()
    }
    #endif

    /// Kullanıcı mesajına streaming yanıt verir. Her parça kümülatif metindir.
    @discardableResult
    func send(_ prompt: String, onPartial: @escaping (String) -> Void) async throws -> String {
        #if canImport(FoundationModels)
        guard let active = session else {
            throw AssistantError(message: "Oturum başlatılamadı. Lütfen ekranı kapatıp tekrar açın.")
        }
        // Önceki yanıt hâlâ sürüyorsa eşzamanlı istek hatasını önle
        if active.isResponding {
            throw AssistantError(message: "Önceki yanıt sürüyor, lütfen bekleyin.")
        }

        do {
            return try await stream(prompt, onPartial: onPartial)
        } catch let genError as LanguageModelSession.GenerationError {
            // Bağlam penceresi dolduysa: oturumu tazele ve bir kez daha dene
            if case .exceededContextWindowSize = genError {
                rebuildSession()
                onPartial("")  // önceki kısmi metni temizle
                do {
                    return try await stream(prompt, onPartial: onPartial)
                } catch {
                    throw AssistantError(message: friendlyMessage(for: error))
                }
            }
            throw AssistantError(message: friendlyMessage(for: genError))
        } catch {
            throw AssistantError(message: friendlyMessage(for: error))
        }
        #else
        throw AssistantError(message: AssistantAvailability.sdkUnavailable.userMessage)
        #endif
    }

    #if canImport(FoundationModels)
    private func stream(_ prompt: String, onPartial: @escaping (String) -> Void) async throws -> String {
        guard let session else { return "" }
        var last = ""
        for try await snapshot in session.streamResponse(to: prompt) {
            last = snapshot.content
            onPartial(last)
        }
        return last
    }

    private func friendlyMessage(for error: Error) -> String {
        if let gen = error as? LanguageModelSession.GenerationError {
            switch gen {
            case .exceededContextWindowSize:
                return "Sohbet çok uzadı. Yeni bir soruyla tekrar deneyin."
            case .guardrailViolation, .refusal:
                return "Bu içerik güvenlik filtresine takıldı. Sorunuzu farklı şekilde ifade edin."
            case .unsupportedLanguageOrLocale:
                return "Bu dil şu an asistan tarafından desteklenmiyor."
            case .rateLimited:
                return "Çok fazla istek gönderildi. Birkaç saniye sonra tekrar deneyin."
            case .assetsUnavailable:
                return "Yapay zekâ modeli şu an hazır değil. Biraz sonra tekrar deneyin."
            case .concurrentRequests:
                return "Önceki yanıt sürüyor, lütfen bekleyin."
            case .decodingFailure, .unsupportedGuide:
                return "Yanıt işlenirken bir sorun oluştu. Tekrar deneyin."
            @unknown default:
                return gen.errorDescription ?? "Beklenmeyen bir hata oluştu."
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
    #endif
}
