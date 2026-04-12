import os.log

extension Logger {
    static let vault = Logger(subsystem: "app.miran.notes", category: "Vault")
    static let editEngine = Logger(subsystem: "app.miran.notes", category: "EditEngine")
}
