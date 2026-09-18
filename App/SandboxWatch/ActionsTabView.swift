import SwiftUI
import SandboxWatchKit

/// start / stop / restart, through the same `SandboxAction` the CLI uses.
///
/// Not a reimplementation: the guards, the confirmation text and the journal all come from the
/// Kit. A second hand-written copy is exactly where journalling a *refusal* gets dropped, and the
/// journal that only records what happened is silent about the afternoon spent wondering why
/// nothing did.
struct ActionsTabView: View {
    struct Model {
        let sandbox: String
        let apps: [String]
        /// Injected rather than built here, so this view never constructs a `SystemProcessRunner`
        /// of its own.
        let client: () -> SandboxAPIClient?
        let runner: ProcessRunner
        let journal: ActionJournal
    }

    let model: Model

    @State private var app: String = ""
    @State private var action: AzAction = .restart
    @State private var context: ActionContext?
    @State private var confirmation: String?
    @State private var refusal: String?
    @State private var outcome: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker(String(localized: "App"), selection: $app) {
                    ForEach(model.apps, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 260)

                Picker(String(localized: "Action"), selection: $action) {
                    ForEach(AzAction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)

                Button(String(localized: "Check")) { Task { await check() } }
                    .disabled(app.isEmpty || busy)
            }

            if let refusal {
                VStack(alignment: .leading, spacing: 4) {
                    Label(String(localized: "Refused"), systemImage: "hand.raised")
                        .foregroundStyle(.red)
                    Text(refusal).font(.callout).textSelection(.enabled)
                }
            }

            if let confirmation {
                VStack(alignment: .leading, spacing: 6) {
                    Text(confirmation).font(.callout.monospaced()).textSelection(.enabled)
                    // Live only once the guards have passed: the button cannot be the thing that
                    // decides whether the action is safe.
                    Button(String(localized: "Run it")) { Task { await run() } }
                        .disabled(context == nil || busy)
                }
            }

            if let outcome {
                Text(outcome).font(.callout).textSelection(.enabled)
            }

            Spacer()
        }
        .padding()
        .onAppear { if app.isEmpty { app = model.apps.first ?? "" } }
    }

    private func check() async {
        busy = true
        defer { busy = false }
        context = nil; confirmation = nil; refusal = nil; outcome = nil

        guard let client = model.client() else {
            refusal = String(localized: "no token in the Keychain")
            return
        }
        switch await SandboxAction.prepare(
            sandbox: model.sandbox, app: app, client: client, runner: model.runner) {
        case .failure(let why):
            // Journalled here as well as in the CLI, by the same function.
            SandboxAction.journal(
                why, sandbox: model.sandbox, app: app, action: action, journal: model.journal)
            refusal = SandboxAction.render(why)
        case .success(let value):
            context = value
            confirmation = SandboxAction.describe(
                value, sandbox: model.sandbox, app: app, action: action)
        }
    }

    private func run() async {
        guard let context else { return }
        busy = true
        defer { busy = false }
        // The context the operator just read is the one the action departs against — the same
        // single pass of the guards the CLI makes.
        outcome = await SandboxAction.perform(
            sandbox: model.sandbox, app: app, action: action, context: context,
            runner: model.runner, journal: model.journal, confirmed: true)
        confirmation = nil
        self.context = nil
    }
}
