import Foundation

enum DockIconPreferenceTests {
    static func run() {
        let suite = "FreeFlowTests.DockIcon.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        TestSupport.expect(DockIconPreference.load(from: defaults), "Installs without a choice must keep hiding the Dock icon")
        TestSupport.expect(defaults.object(forKey: DockIconPreference.storageKey) == nil, "Loading the default must not persist a choice")

        for hidden in [true, false] {
            defaults.set(hidden, forKey: DockIconPreference.storageKey)
            TestSupport.expectEqual(DockIconPreference.load(from: UserDefaults(suiteName: suite)!), hidden)
        }

        TestSupport.expect(DockIconPreference.showsInDock(hasOpenWindow: true, hideWhenClosed: true), "An open window must show the Dock icon")
        TestSupport.expect(DockIconPreference.showsInDock(hasOpenWindow: true, hideWhenClosed: false), "An open window must show the Dock icon")
        TestSupport.expect(!DockIconPreference.showsInDock(hasOpenWindow: false, hideWhenClosed: true), "Closing the window must hide the icon when the setting is on")
        TestSupport.expect(DockIconPreference.showsInDock(hasOpenWindow: false, hideWhenClosed: false), "Closing the window must keep the icon when the setting is off")
    }
}
