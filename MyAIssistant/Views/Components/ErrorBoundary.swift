import SwiftUI
import os

/// Centralized error state observable across the app.
/// Views post errors here; the boundary modifier displays them.
@MainActor
final class ErrorReporter: ObservableObject {
    static let shared = ErrorReporter()

    @Published var currentError: String?

    private let logger = Logger(subsystem: "com.myaissistant.app", category: "errors")

    func report(_ error: Error, context: String = "") {
        let message = context.isEmpty
            ? error.localizedDescription
            : "\(context): \(error.localizedDescription)"
        logger.error("\(message)")
        currentError = message

        // Auto-dismiss after 6 seconds
        Task {
            try? await Task.sleep(for: .seconds(6))
            if currentError == message {
                withAnimation { currentError = nil }
            }
        }
    }

    func dismiss() {
        withAnimation { currentError = nil }
    }
}

/// View modifier that overlays a dismissible error banner at the top of the view.
struct ErrorBoundaryModifier: ViewModifier {
    @ObservedObject private var reporter = ErrorReporter.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let error = reporter.currentError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppFonts.body(14))
                    Text(error)
                        .font(AppFonts.label(13))
                        .lineLimit(2)
                    Spacer()
                    Button {
                        reporter.dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppFonts.body(16))
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppColors.overdueRed.opacity(0.9))
                .cornerRadius(12)
                .shadow(color: AppColors.textPrimary.opacity(0.15), radius: 8, y: 4)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: reporter.currentError)
    }
}

extension View {
    func withErrorBoundary() -> some View {
        modifier(ErrorBoundaryModifier())
    }
}
