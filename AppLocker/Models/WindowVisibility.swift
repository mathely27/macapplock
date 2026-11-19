/// Some Mac Catalyst apps report AXWindows = [] while an ordinary app window is onscreen.
/// Never let that incomplete accessibility snapshot override visible WindowServer windows.
struct WindowVisibility {
    static func shouldIntercept(explicitOpen: Bool, accessibilityWindowCount: Int?, visibleWindowCount: Int?) -> Bool {
        if explicitOpen { return true }
        if let visibleWindowCount, visibleWindowCount > 0 { return true }
        if let accessibilityWindowCount, accessibilityWindowCount > 0 { return true }
        if visibleWindowCount == nil && accessibilityWindowCount == nil { return true }
        return false
    }
}
