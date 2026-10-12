import Foundation
import Security

struct UniFlowSession: Codable {
    var accessToken: String
    var refreshToken: String
    var userId: String
    var expiresAt: Date
}

enum SecureSession {
    private static let service = "com.uniflow.widgets.session"
    static func load() -> UniFlowSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "current",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(UniFlowSession.self, from: data)
    }
    static func save(_ session: UniFlowSession) throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "current"]
        SecItemDelete(query as CFDictionary)
        var values = query
        values[kSecValueData as String] = data
        let code = SecItemAdd(values as CFDictionary, nil)
        guard code == errSecSuccess else { throw URLError(.userAuthenticationRequired) }
    }
    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service, kSecAttrAccount as String: "current"] as CFDictionary)
    }
}

struct AuthReply: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int
    let user: AuthUser?
}
struct AuthUser: Decodable { let id: String }
struct WorkspaceRow: Decodable { let payload: UniFlowWorkspace }

struct SupabaseClient {
    let endpoint: URL
    let publicKey: String

    static var configured: SupabaseClient? {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "UniFlowSupabaseURL") as? String,
              let url = URL(string: urlString), url.scheme == "https", url.host != nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "UniFlowSupabaseKey") as? String,
              !key.isEmpty, !key.contains("$(") else { return nil }
        return SupabaseClient(endpoint: url, publicKey: key)
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil, token: String? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: endpoint)?.absoluteURL else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(publicKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (bytes, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            throw NSError(domain: "UniFlow Supabase", code: response.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Supabase (\(response.statusCode)): " + (String(data: bytes, encoding: .utf8) ?? "Unbekannter Fehler").prefix(250).description])
        }
        return bytes
    }

    func sendCode(to email: String) async throws {
        let json = try JSONSerialization.data(withJSONObject: ["email": email, "create_user": false])
        _ = try await request("/auth/v1/otp", method: "POST", body: json)
    }
    func verify(email: String, code: String) async throws -> UniFlowSession {
        let json = try JSONSerialization.data(withJSONObject: ["email": email, "token": code, "type": "email"])
        let raw = try await request("/auth/v1/verify", method: "POST", body: json)
        let result = try JSONDecoder().decode(AuthReply.self, from: raw)
        guard let userId = result.user?.id else { throw URLError(.userAuthenticationRequired) }
        return UniFlowSession(accessToken: result.access_token, refreshToken: result.refresh_token,
                              userId: userId, expiresAt: Date().addingTimeInterval(TimeInterval(result.expires_in)))
    }
    func validSession(_ session: UniFlowSession) async throws -> UniFlowSession {
        if session.expiresAt > Date().addingTimeInterval(120) { return session }
        let json = try JSONSerialization.data(withJSONObject: ["refresh_token": session.refreshToken])
        let raw = try await request("/auth/v1/token?grant_type=refresh_token", method: "POST", body: json)
        let reply = try JSONDecoder().decode(AuthReply.self, from: raw)
        let updated = UniFlowSession(accessToken: reply.access_token, refreshToken: reply.refresh_token,
                              userId: reply.user?.id ?? session.userId, expiresAt: Date().addingTimeInterval(TimeInterval(reply.expires_in)))
        try SecureSession.save(updated)
        return updated
    }
    func workspace(for session: UniFlowSession) async throws -> UniFlowWorkspace {
        // The authenticated user's own private workspace is protected by Supabase RLS.
        guard let userId = session.userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { throw URLError(.badURL) }
        let raw = try await request("/rest/v1/private_workspaces?select=payload&user_id=eq.\(userId)", token: session.accessToken)
        let rows = try JSONDecoder().decode([WorkspaceRow].self, from: raw)
        return rows.first?.payload ?? UniFlowWorkspace()
    }
}

