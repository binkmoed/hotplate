import SwiftUI
import UIKit

/// First-run / reconfiguration screen: enter the hotplate controller host and port,
/// validate via `GET /api/stats`, then connect.
struct ConnectionSetupView: View {
    @Environment(HotplateClient.self) private var client

    @State private var host: String = "192.168.178.120"
    @State private var port: String = "8080"
    @State private var isValidating = false
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Host (e.g. 192.168.178.120)", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Server")
                } footer: {
                    Text("Enter the IP address and port of your hotplate controller.")
                }

                if let validationError {
                    Section {
                        Label(validationError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            if isValidating { ProgressView().controlSize(.small) }
                            Text(isValidating ? "Validating…" : "Connect")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(host.isEmpty || port.isEmpty || isValidating)
                }

                if client.connection != nil {
                    Section {
                        Button("Forget saved server", role: .destructive) {
                            client.forgetConnection()
                        }
                    }
                }
            }
            .navigationTitle("Hotplate")
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                }
            }
            .onAppear {
                if let saved = client.connection {
                    host = saved.host
                    port = String(saved.port)
                }
            }
        }
    }

    private func connect() async {
        isValidating = true
        validationError = nil
        defer { isValidating = false }

        guard let portValue = Int(port), (1...65535).contains(portValue) else {
            validationError = "Port must be between 1 and 65535."
            return
        }
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        Logger.shared.debug("Attempting connection to \(trimmed):\(portValue)")
        let connection = ServerConnection(host: trimmed, port: portValue)
        await client.connect(to: connection)

        if case .failed(let msg) = client.phase {
            Logger.shared.error("Connection failed: \(msg)")
            validationError = "Cannot connect to server"
        } else if client.phase == .connected {
            Logger.shared.info("Connection successful")
        }
    }
}
