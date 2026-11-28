import SwiftUI
import AppKit

/// Обёртка для переноса NSImage между потоками (NSImage не Sendable).
private struct SendableImage: @unchecked Sendable { let image: NSImage }

/// NSImageView с включённой анимацией GIF. `animates = false` показывает
/// первый кадр — используется, когда сообщение ушло из viewport.
struct AnimatedGifImage: NSViewRepresentable {
    let image: NSImage
    let animates: Bool

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.image = image
        view.animates = animates
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if view.image !== image { view.image = image }
        if view.animates != animates { view.animates = animates }
    }
}

/// Отображение GIF: данные берутся из GifLoader (кэш + дедупликация),
/// декодирование — вне главного потока, анимация — только у видимых строк.
///
/// - Размер: максимум 320×240 pt, пропорции сохраняются.
/// - Место резервируется ДО загрузки (запасное соотношение 4:3), после
///   загрузки высота меняется один раз.
/// - Состояния: загрузка (заглушка с индикатором), ошибка ("GIF недоступен" + ссылка).
struct GifView: View {
    let source: GifSource
    let accessToken: String
    /// Анимация включена только когда строка находится в viewport.
    var isVisible: Bool = true
    let onOpenLink: () -> Void

    @State private var image: NSImage?
    @State private var loadError = false
    @State private var resolvedSize: CGSize = CGSize(width: 320, height: 240) // резерв 4:3

    var body: some View {
        Group {
            if loadError {
                errorView
            } else if let image {
                AnimatedGifImage(image: image, animates: isVisible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenLink() }
            } else {
                loadingView
            }
        }
        // Обёртка вписывает GIF в доступное место: картинка уменьшается по
        // ширине/высоте с сохранением пропорций и не выходит за видимый край.
        // Без `.cornerRadius` / `clipShape`, поэтому углы не обрезаются.
        .aspectRatio(resolvedSize.width / resolvedSize.height, contentMode: .fit)
        .frame(maxWidth: resolvedSize.width, maxHeight: resolvedSize.height)
        // Загрузка НЕ привязана к жизненному циклу строки: GifLoader создаёт
        // detached-задачу, уход из viewport её не отменяет.
        .task {
            let data = await GifLoader.shared.load(
                messageId: source.messageId,
                url: source.url,
                accessToken: accessToken
            )
            guard let data else {
                loadError = true
                return
            }
            // Декодирование NSImage — вне главного потока.
            let box = await Task.detached(priority: .utility) {
                NSImage(data: data).map { SendableImage(image: $0) }
            }.value
            guard let decoded = box?.image else {
                loadError = true
                return
            }
            if decoded.size.width > 0, decoded.size.height > 0 {
                let scale = min(320 / decoded.size.width, 240 / decoded.size.height, 1)
                resolvedSize = CGSize(width: decoded.size.width * scale,
                                      height: decoded.size.height * scale)
            }
            image = decoded
        }
    }

    private var loadingView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.15))
            .overlay {
                ProgressView()
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1))
                .overlay {
                    Text("GIF недоступен")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            Button("Открыть ссылку") {
                onOpenLink()
            }
            .font(.caption2)
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
