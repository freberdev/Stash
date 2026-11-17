import SwiftUI

/// Shows the current shortcut. Click it, then press the new combination.
struct ShortcutRecorder: View {
    let model: AppModel

    var body: some View {
        Button {
            if model.isRecordingShortcut {
                model.stopRecordingShortcut()
            } else {
                model.startRecordingShortcut()
            }
        } label: {
            Text(model.isRecordingShortcut ? L("settings.shortcut.recording") : model.shortcutDisplay)
                .frame(minWidth: 130)
        }
        .accessibilityLabel(L("settings.shortcut.change"))
        .accessibilityValue(model.shortcutDisplay)
    }
}
