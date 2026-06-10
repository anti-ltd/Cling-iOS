/**
 The share-sheet composer. Shows what arrived, lets the user pick note vs.
 clipboard for text, add a caption to an image, and saves a *pending* pin —
 with the iOS rule ("only the app itself can place pins in the Dynamic
 Island") said plainly, plus an immediate local notification as the hand-off.
 */
import SwiftUI
import UserNotifications
import iUXiOS

struct ShareComposeView: View {
    let extractor: () async -> SharedContent
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var content: SharedContent?
    @State private var typeID: PinTypeID = .clipboard
    @State private var caption = ""
    @State private var saved = false

    var body: some View {
        VStack(spacing: UX.cardSpacing) {
            HStack {
                Button("Cancel", action: onCancel)
                    .font(.callout)
                Spacer()
                Text("Pin with Cling")
                    .font(.headline)
                Spacer()
                // Mirror Cancel's width so the title centres.
                Button("Cancel") {}.font(.callout).hidden()
            }

            if saved {
                savedState
            } else if let content {
                composer(content)
            } else {
                ProgressView()
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(UX.screenPadding)
        .background {
            AmbientBackdrop(tint: PinAppearance.indigo.color)
                .ignoresSafeArea()
        }
        .task {
            let extracted = await extractor()
            content = extracted
            // Text from a page share reads as "keep this handy" → clipboard;
            // an image is a note with a photo.
            typeID = extracted.imageData != nil ? .note : .clipboard
            if let text = extracted.text { caption = text }
        }
    }

    // MARK: - Compose

    @ViewBuilder private func composer(_ content: SharedContent) -> some View {
        VStack(spacing: UX.cardSpacing) {
            if content.imageData == nil {
                // Text/URL shares can be a clipboard pin or a note.
                HStack(spacing: 8) {
                    ForEach([PinTypeID.clipboard, .note], id: \.self) { candidate in
                        Chip(
                            candidate == .clipboard ? "Clipboard" : "Note",
                            systemImage: candidate == .clipboard ? "doc.on.clipboard" : "note.text",
                            isSelected: typeID == candidate
                        ) {
                            withAnimation(UX.Motion.morph) { typeID = candidate }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            CardSection {
                if let imageData = content.imageData, let image = UIImage(data: imageData) {
                    HStack {
                        Spacer()
                        GlassThumb(
                            image: Image(uiImage: image),
                            size: CGSize(width: 120, height: 120))
                        Spacer()
                    }
                    .padding(.vertical, UX.rowVPadding)
                }
                TextFieldRow(
                    prompt: content.imageData != nil ? "Add a caption (optional)" : "Text to pin",
                    text: $caption,
                    axis: .vertical)
                if let url = content.url {
                    Text(url.host() ?? url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
            }

            Button(action: save) {
                Label("Save pin", systemImage: "pin.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        Capsule().fill(PinAppearance.indigo.color)
                            .overlay(
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [.white.opacity(UX.Glass.sheenTopOpacity), .clear],
                                        startPoint: .top, endPoint: .bottom)
                                )
                            )
                    }
                    .foregroundStyle(.white)
            }
            .buttonStyle(.glassBloom)
            .disabled(!savable(content))
            .opacity(savable(content) ? 1 : 0.5)

            Spacer(minLength: 0)
        }
    }

    /// Post-save: honest about the platform rule, with the hand-off spelled out.
    private var savedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(PinAppearance.mint.color)
            Text("Saved")
                .font(.headline)
            Text("iOS only lets the app itself place pins in the Dynamic Island. Open Cling — or tap the notification we just sent — and it's pinned.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onDone) {
                Text("Done")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassBloom)
            .glassPill(tint: PinAppearance.indigo.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .glassCard()
    }

    private func savable(_ content: SharedContent) -> Bool {
        content.imageData != nil
            || !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Save + hand-off

    private func save() {
        guard let content else { return }
        let store = ClingStore.shared
        let settings = store.loadSettings()

        var photoFilename: String?
        if let imageData = content.imageData, let image = UIImage(data: imageData) {
            photoFilename = PhotoStore.shared.save(image)
        }

        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: PinPayload =
            if photoFilename != nil || typeID == .note {
                .note(NotePayload(text: text, photoFilename: photoFilename))
            } else {
                .clipboard(ClipboardPayload(text: text, sourceURL: content.url))
            }

        let pin = Pin(
            payload: payload,
            appearance: settings.defaultAppearance(for: payload.typeID),
            status: .pending)
        store.upsert(pin)  // posts the Darwin notification — a running app sweeps immediately

        scheduleHandOffNotification(for: pin)
        withAnimation(UX.Motion.morph) { saved = true }
    }

    /// The reliable half of the hand-off: a notification that opens the app,
    /// which activates the pending pin. (Notification permission is the app's
    /// to ask; if it was never granted this is quietly dropped and the pin
    /// still activates on next open.)
    private func scheduleHandOffNotification(for pin: Pin) {
        let content = UNMutableNotificationContent()
        content.title = "Saved — tap to pin it"
        content.body = "Open Cling to place it in your Dynamic Island."
        content.userInfo = ["pinID": pin.id.uuidString]
        content.categoryIdentifier = "PIN_RENEWAL"  // same tap-to-activate route
        let request = UNNotificationRequest(
            identifier: "handoff-\(pin.id.uuidString)",
            content: content,
            trigger: nil)  // immediate
        UNUserNotificationCenter.current().add(request)
    }
}
