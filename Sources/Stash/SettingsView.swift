import StashCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var loginItemFailed = false

    var body: some View {
        Form {
            Section {
                LabeledContent(L("settings.shortcut.label")) {
                    ShortcutRecorder(model: model)
                }
                Text(model.shortcutMessage ?? L("settings.shortcut.hint"))
                    .font(.callout)
                    .foregroundStyle(model.shortcutMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle(L("settings.login.label"), isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, enabled in
                        guard enabled != LoginItem.isEnabled else { return }
                        do {
                            try LoginItem.setEnabled(enabled)
                            loginItemFailed = false
                        } catch {
                            loginItemFailed = true
                            opensAtLogin = LoginItem.isEnabled
                        }
                    }
                if loginItemFailed {
                    Text(L("settings.login.failed"))
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Picker(L("settings.retention.label"), selection: retention) {
                    Text(L("settings.retention.never")).tag(Retention.never)
                    Text(L("settings.retention.oneDay")).tag(Retention.oneDay)
                    Text(L("settings.retention.oneWeek")).tag(Retention.oneWeek)
                    Text(L("settings.retention.oneMonth")).tag(Retention.oneMonth)
                }
                Text(L("settings.retention.hint"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Picker(L("settings.language.label"), selection: language) {
                    Text(L("settings.language.system")).tag(AppLanguage.system)
                    // Each language is named in its own words, so it can be found from the other one.
                    Text(verbatim: "Svenska").tag(AppLanguage.swedish)
                    Text(verbatim: "English").tag(AppLanguage.english)
                }
                Text(L("settings.language.hint"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(L("settings.files.title")) {
                Text(L("settings.files.references"))
                Text(L("settings.files.copies"))
                Text(L("settings.files.privacy"))
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var language: Binding<AppLanguage> {
        Binding { model.language } set: { model.setLanguage($0) }
    }

    private var retention: Binding<Retention> {
        Binding { model.retention } set: { model.setRetention($0) }
    }
}
