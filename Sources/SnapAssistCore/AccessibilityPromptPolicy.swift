public enum AccessibilityPromptPolicy {
    public static func shouldPrompt(isTrusted: Bool, hasRequestedBefore: Bool) -> Bool {
        !isTrusted && !hasRequestedBefore
    }
}

