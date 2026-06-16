#!/usr/bin/env bash
#
# guard-no-native-tabbar.sh
#
# Regression guard for the iOS 26 "Liquid Glass" tab-bar pill bug.
#
# Symptom: a draggable horizontal pill appears on screen and scrubs between the
# four tabs (Coach / Today / Compass / Settings). It is the system tab-bar lens
# (_UITabBarPlatterView + _UILiquidLensView) leaking through a native TabView
# whose chrome was hidden via `.toolbar(.hidden, for: .tabBar)`.
#
# The fix replaces the native TabView in ContentView with a custom ZStack of
# opacity-gated subtrees + CustomTabBar (no native tab bar exists, so nothing
# can leak). This script fails the build if that fix is ever reverted.
#
# Onboarding deliberately uses a `.page` TabView (a pager, not a tab bar) and is
# NOT a tab-bar leak, so the native-TabView check is scoped to ContentView only.
#
# Run locally:  bash scripts/guard-no-native-tabbar.sh
# In CI:        add as a step before/after the test job.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

content_view="MyAIssistant/ContentView.swift"
fail=0

# 1. No native root TabView in ContentView (matches `TabView(` or `TabView {`,
#    not the word "TabView" inside a comment/backtick).
if grep -nE '(^|[^A-Za-z])TabView[[:space:]]*[({]' "$content_view"; then
  echo "::error file=${content_view}::Native TabView reintroduced in ContentView — this risks the iOS 26 Liquid Glass draggable-pill regression. Use the custom ZStack + CustomTabBar pattern instead."
  fail=1
fi

# 2. No `.toolbar(.hidden, for: .tabBar)` anywhere in the app target — that is the
#    specific modifier that lets the system tab-bar lens leak through.
if grep -rnE 'toolbar\([[:space:]]*\.hidden[[:space:]]*,[[:space:]]*for:[[:space:]]*\.tabBar[[:space:]]*\)' MyAIssistant/; then
  echo "::error::.toolbar(.hidden, for: .tabBar) reintroduced — this is what leaks the system tab-bar pill under Liquid Glass."
  fail=1
fi

# 3. Onboarding must not reintroduce a native pager. A page-style TabView is a
#    UIPageViewController whose chrome can leak the same Liquid Glass lens, and
#    its horizontal swipe bypasses each screen's Continue / Skip validation
#    gates. The onboarding flow uses a manual ZStack page container instead.
onboarding="MyAIssistant/Views/Onboarding/OnboardingContainerView.swift"
if grep -nE '(^|[^A-Za-z])TabView[[:space:]]*[({]|tabViewStyle\([[:space:]]*\.page' "$onboarding"; then
  echo "::error file=${onboarding}::Native page TabView reintroduced in onboarding — use the manual ZStack page container instead."
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "guard-no-native-tabbar: OK — no native TabView, hidden-tabBar toolbar, or onboarding pager found."
fi

exit "$fail"
