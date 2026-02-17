import SwiftUI

struct SubscriptionView: View {
    @Environment(\.subscriptionTier) private var currentTier
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var selectedBilling: BillingPeriod = .monthly

    private enum BillingPeriod {
        case monthly, annual
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Current tier badge
                currentTierBadge

                // Billing toggle
                billingToggle

                // Plan cards
                ForEach([SubscriptionTier.pro, .student, .powerUser]) { tier in
                    planCard(tier: tier)
                }

                // Restore purchases
                Button {
                    Task { await subscriptionManager.restore() }
                } label: {
                    Text("Restore Purchases")
                        .font(AppFonts.body(14))
                        .foregroundColor(AppColors.textMuted)
                }
                .padding(.top, 8)

                // Error message
                if let error = subscriptionManager.lastError {
                    Text(error)
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.coral)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await subscriptionManager.loadProducts()
        }
    }

    // MARK: - Current Tier Badge

    private var currentTierBadge: some View {
        HStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 20))
                .foregroundColor(currentTier == .free ? AppColors.textMuted : AppColors.accentWarm)

            VStack(alignment: .leading, spacing: 2) {
                Text("Current Plan")
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textMuted)
                Text(currentTier.displayName)
                    .font(AppFonts.heading(18))
                    .foregroundColor(AppColors.textPrimary)
            }

            Spacer()
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Billing Toggle

    private var billingToggle: some View {
        HStack(spacing: 0) {
            billingButton("Monthly", period: .monthly)
            billingButton("Annual (Save 37%)", period: .annual)
        }
        .background(AppColors.surface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func billingButton(_ label: String, period: BillingPeriod) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedBilling = period
            }
        } label: {
            Text(label)
                .font(AppFonts.bodyMedium(13))
                .foregroundColor(selectedBilling == period ? .white : AppColors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selectedBilling == period ? AppColors.accent : Color.clear)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .padding(2)
    }

    // MARK: - Plan Card

    private func planCard(tier: SubscriptionTier) -> some View {
        let isCurrent = tier == currentTier
        let price = selectedBilling == .monthly ? tier.monthlyPrice : tier.annualPrice
        let productID = selectedBilling == .monthly ? tier.monthlyProductID : tier.annualProductID

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tier.displayName)
                    .font(AppFonts.heading(18))
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Text(price)
                    .font(AppFonts.bodyMedium(16))
                    .foregroundColor(AppColors.accent)
            }

            ForEach(tier.features, id: \.self) { feature in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.accentWarm)
                    Text(feature)
                        .font(AppFonts.body(14))
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            if isCurrent {
                Text("Current Plan")
                    .font(AppFonts.bodyMedium(14))
                    .foregroundColor(AppColors.accentWarm)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColors.accentWarm.opacity(0.1))
                    .cornerRadius(10)
            } else if let productID, let product = subscriptionManager.product(for: productID) {
                Button {
                    Task { _ = await subscriptionManager.purchase(product) }
                } label: {
                    HStack {
                        if subscriptionManager.purchaseInProgress {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        }
                        Text("Subscribe")
                            .font(AppFonts.bodyMedium(15))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColors.accent)
                    .cornerRadius(10)
                }
                .disabled(subscriptionManager.purchaseInProgress)
            } else {
                Text("Subscribe")
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColors.textMuted)
                    .cornerRadius(10)
            }
        }
        .padding(16)
        .background(
            isCurrent
                ? AnyShapeStyle(LinearGradient(
                    colors: [AppColors.accentWarm.opacity(0.06), AppColors.accent.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                  ))
                : AnyShapeStyle(AppColors.card)
        )
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isCurrent ? AppColors.accentWarm.opacity(0.3) : AppColors.border.opacity(0.5), lineWidth: 1)
        )
    }
}
