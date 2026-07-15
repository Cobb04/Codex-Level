import Carbon.HIToolbox
import Testing
@testable import CodexLevelApp

@Suite struct CodexLevelShortcutTests {
    @Test func defaultShortcutIsOptionL() {
        let shortcut = CodexLevelShortcut.default

        #expect(shortcut.keyCode == UInt32(kVK_ANSI_L))
        #expect(shortcut.modifiers == UInt32(optionKey))
    }

    @MainActor
    @Test func shortcutActionRequestsOnePanelToggle() {
        var toggleCount = 0
        let shortcut = CodexLevelShortcut.default

        shortcut.perform {
            toggleCount += 1
        }

        #expect(toggleCount == 1)
    }

    @Test(arguments: [
        (false, PopoverToggleAction.show),
        (true, PopoverToggleAction.close),
    ])
    func toggleShowsAClosedPanelAndClosesAnOpenPanel(
        isPopoverShown: Bool,
        expected: PopoverToggleAction
    ) {
        #expect(PopoverToggleAction.next(isPopoverShown: isPopoverShown) == expected)
    }
}
