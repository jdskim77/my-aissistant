import Foundation

// MARK: - Minimal stubs for types needed by shared model files
// These types are defined fully in the main app but the extension only needs
// them to satisfy the compiler for SwiftData schema registration.

#if !MAIN_APP_TARGET

/// Stub for SubscriptionTier — the real enum lives in AIProviderFactory.swift
/// which has too many dependencies for the extension. The extension never calls
/// these methods; they're only needed because UsageTracker references the type.
enum SubscriptionTier: String {
    case free
    case pro
    case student
    case powerUser
}

#endif
