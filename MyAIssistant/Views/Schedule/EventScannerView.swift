import SwiftUI
import PhotosUI

/// Scans an image (photo or camera) for event details using Claude Vision,
/// shows a confirmation card, and creates the task/calendar event on confirm.
struct EventScannerView: View {
    @Environment(\.taskManager) private var taskManager
    @Environment(\.calendarSyncManager) private var calendarSyncManager
    @Environment(\.keychainService) private var keychainService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var showingCamera = false

    // Scan state
    @State private var isScanning = false
    @State private var scanError: String?
    @State private var scannedEvent: ScannedEvent?

    struct ScannedEvent {
        var title: String
        var date: Date
        var endDate: Date
        var location: String
        var notes: String
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Image preview or picker
                    if let imageData, let uiImage = UIImage(data: imageData) {
                        imagePreview(uiImage)
                    } else {
                        pickerButtons
                    }

                    // Scanning state
                    if isScanning {
                        scanningIndicator
                    }

                    // Error
                    if let scanError {
                        errorBanner(scanError)
                    }

                    // Result confirmation
                    if let event = scannedEvent {
                        confirmationCard(event)
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Scan Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                Task { await loadPhoto(newItem) }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPickerView { image in
                    if let data = image.jpegData(compressionQuality: 0.7) {
                        imageData = data
                        scanImage(data: data, mediaType: "image/jpeg")
                    }
                }
            }
        }
    }

    // MARK: - Picker Buttons

    private var pickerButtons: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 52))
                .foregroundColor(AppColors.accent)

            Text("Scan an event")
                .font(AppFonts.heading(20))
                .foregroundColor(AppColors.textPrimary)

            Text("Take a photo or choose an image of a flyer, poster, invitation, or screenshot to add it to your schedule.")
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button {
                    Haptics.light()
                    showingCamera = true
                } label: {
                    Label("Camera", systemImage: "camera.fill")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.accent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(AppColors.accentLight)
                        .cornerRadius(16)
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.accent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(AppColors.accentLight)
                        .cornerRadius(16)
                }
            }
        }
        .padding(24)
    }

    // MARK: - Image Preview

    private func imagePreview(_ image: UIImage) -> some View {
        VStack(spacing: 12) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.1), radius: 8, y: 4)

            if scannedEvent == nil && !isScanning {
                Button {
                    Haptics.light()
                    imageData = nil
                    selectedPhoto = nil
                    scannedEvent = nil
                    scanError = nil
                } label: {
                    Text("Choose a different image")
                        .font(AppFonts.bodyMedium(14))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    // MARK: - Scanning Indicator

    private var scanningIndicator: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Scanning for event details...")
                .font(AppFonts.bodyMedium(14))
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(20)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(AppFonts.body(13))
                .foregroundColor(AppColors.textPrimary)
            Spacer()
            Button {
                scanError = nil
                imageData = nil
                selectedPhoto = nil
            } label: {
                Text("Try Again")
                    .font(AppFonts.bodyMedium(13))
                    .foregroundColor(AppColors.accent)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.red.opacity(0.08))
        )
    }

    // MARK: - Confirmation Card

    private func confirmationCard(_ event: ScannedEvent) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppColors.completionGreen)
                Text("Event Found")
                    .font(AppFonts.heading(16))
                    .foregroundColor(AppColors.textPrimary)
            }

            VStack(alignment: .leading, spacing: 10) {
                eventDetailRow(icon: "text.alignleft", label: "Title", value: event.title)
                eventDetailRow(icon: "calendar", label: "Date", value: event.date.formatted(as: "EEE, MMM d, yyyy"))
                eventDetailRow(icon: "clock", label: "Time", value: "\(event.date.formatted(as: "h:mm a")) – \(event.endDate.formatted(as: "h:mm a"))")
                if !event.location.isEmpty {
                    eventDetailRow(icon: "mappin", label: "Location", value: event.location)
                }
                if !event.notes.isEmpty {
                    eventDetailRow(icon: "note.text", label: "Notes", value: event.notes)
                }
            }

            HStack(spacing: 12) {
                Button {
                    Haptics.light()
                    scannedEvent = nil
                    imageData = nil
                    selectedPhoto = nil
                } label: {
                    Text("Discard")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background(AppColors.surface)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
                }

                Button {
                    Haptics.success()
                    createEvent(event)
                } label: {
                    Text("Add to Schedule")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background(AppColors.accent)
                        .cornerRadius(16)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.card)
                .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)
        )
    }

    private func eventDetailRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppColors.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppFonts.caption(11))
                    .foregroundColor(AppColors.textMuted)
                Text(value)
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textPrimary)
            }
        }
    }

    // MARK: - Logic

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            scanError = "Could not load the selected image."
            return
        }
        await MainActor.run {
            imageData = data
        }
        let mediaType = "image/jpeg" // PhotosPicker returns compatible formats
        scanImage(data: data, mediaType: mediaType)
    }

    private func scanImage(data: Data, mediaType: String) {
        guard let apiKey = keychainService.anthropicAPIKey(), !apiKey.isEmpty else {
            scanError = "No API key configured. Add your Claude API key in Settings."
            return
        }

        isScanning = true
        scanError = nil
        scannedEvent = nil

        let today = Date().formatted(as: "yyyy-MM-dd")

        Task {
            do {
                let provider = AnthropicProvider(apiKey: apiKey)
                let response = try await provider.sendVisionMessage(
                    prompt: """
                    Extract event details from this image. Today's date is \(today).

                    Return ONLY a JSON object with these fields (no other text):
                    {
                      "title": "Event name",
                      "date": "YYYY-MM-DD",
                      "start_time": "HH:mm",
                      "end_time": "HH:mm",
                      "location": "Location or empty string",
                      "notes": "Any additional details or empty string"
                    }

                    If you cannot find event details, return: {"error": "No event found in this image"}
                    If the year is ambiguous, assume the next occurrence from today.
                    If no end time is clear, assume 1 hour after start.
                    """,
                    imageData: data,
                    mediaType: mediaType
                )

                await MainActor.run {
                    isScanning = false
                    parseVisionResponse(response.content)
                }
            } catch {
                await MainActor.run {
                    isScanning = false
                    scanError = "Failed to scan: \(error.localizedDescription)"
                }
            }
        }
    }

    private func parseVisionResponse(_ text: String) {
        // Extract JSON from response (Claude may wrap it in markdown code blocks)
        var jsonText = text
        if let start = jsonText.range(of: "{"), let end = jsonText.range(of: "}", options: .backwards) {
            jsonText = String(jsonText[start.lowerBound...end.upperBound])
        }

        guard let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            scanError = "Could not parse event details from image."
            return
        }

        if let error = json["error"] as? String {
            scanError = error
            return
        }

        guard let title = json["title"] as? String,
              let dateStr = json["date"] as? String,
              let startTime = json["start_time"] as? String else {
            scanError = "Could not extract event details. Try a clearer image."
            return
        }

        let endTime = json["end_time"] as? String ?? ""
        let location = json["location"] as? String ?? ""
        let notes = json["notes"] as? String ?? ""

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        guard let startDate = dateFormatter.date(from: "\(dateStr) \(startTime)") else {
            scanError = "Could not parse the event date/time."
            return
        }

        let endDate: Date
        if !endTime.isEmpty, let parsed = dateFormatter.date(from: "\(dateStr) \(endTime)") {
            endDate = parsed
        } else {
            endDate = Calendar.current.safeDate(byAdding: .hour, value: 1, to: startDate)
        }

        scannedEvent = ScannedEvent(
            title: title,
            date: startDate,
            endDate: endDate,
            location: location,
            notes: notes
        )
    }

    private func createEvent(_ event: ScannedEvent) {
        let notesText = [event.notes, event.location.isEmpty ? "" : "📍 \(event.location)"]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let task = TaskItem(
            title: event.title,
            category: .personal,
            priority: .medium,
            date: event.date,
            icon: "📸",
            notes: notesText
        )
        taskManager?.addTask(task)
        Haptics.success()
        dismiss()
    }
}

// MARK: - Camera Picker (UIKit wrapper)

struct CameraPickerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
