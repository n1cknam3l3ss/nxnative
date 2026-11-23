// Discord Rich Presence Gateway & Login integration for iOS.
// Connects directly to Discord Gateway (wss://gateway.discord.gg) using native iOS URLSessionWebSocketTask.
// Allows fully standalone Rich Presence from iPhone without requiring a computer.
import Foundation
import WebKit
import SwiftUI
import Combine

public final class DiscordGateway: NSObject, URLSessionWebSocketDelegate {
    public static let shared = DiscordGateway()

    private var webSocketTask: URLSessionWebSocketTask?
    private var heartbeatTimer: Timer?
    private var sequence: Int?
    private var gameName: String = ""
    private var gameId: String = ""
    private var currentDesc: String = ""
    private var startTime: Int = 0
    private var isIdentified = false
    private let queue = DispatchQueue(label: "com.nxnative.discord.gateway", qos: .utility)

    public func start(gameName: String, gameId: String) {
        guard let token = UserDefaults.standard.string(forKey: "discord_token"), !token.isEmpty else {
            return
        }
        self.gameName = gameName
        self.gameId = gameId
        self.startTime = Int(Date().timeIntervalSince1970)
        connect(token: token)
    }

    private func connect(token: String) {
        stop()
        let url = URL(string: "wss://gateway.discord.gg/?v=10&encoding=json")!
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage(token: token)
    }

    private func receiveMessage(token: String) {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleGatewayPayload(text, token: token)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleGatewayPayload(text, token: token)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage(token: token)
            case .failure(let error):
                fputs("[discord-gateway] connection error: \(error.localizedDescription)\n", stderr)
                self.reconnect(token: token)
            }
        }
    }

    private func handleGatewayPayload(_ text: String, token: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let op = json["op"] as? Int else { return }

        if let s = json["s"] as? Int {
            self.sequence = s
        }

        switch op {
        case 10: // HELLO: server sends heartbeat interval
            if let d = json["d"] as? [String: Any],
               let intervalMs = d["heartbeat_interval"] as? Double {
                startHeartbeat(interval: intervalMs / 1000.0)
                sendIdentify(token: token)
            }
        case 1: // HEARTBEAT requested by server
            sendHeartbeat()
        case 7, 9: // RECONNECT / INVALID_SESSION
            reconnect(token: token)
        case 11: // HEARTBEAT_ACK
            break
        case 0: // DISPATCH
            let t = json["t"] as? String
            if t == "READY" {
                self.isIdentified = true
                sendPresenceUpdate()
            }
        default:
            break
        }
    }

    private func startHeartbeat(interval: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            self?.heartbeatTimer?.invalidate()
            self?.heartbeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                self?.sendHeartbeat()
            }
        }
    }

    private func sendHeartbeat() {
        let payload: [String: Any] = [
            "op": 1,
            "d": sequence as Any
        ]
        sendJSON(payload)
    }

    private func sendIdentify(token: String) {
        let presence: [String: Any] = [
            "status": "online",
            "since": 0,
            "activities": [buildActivity()],
            "afk": false
        ]

        let payload: [String: Any] = [
            "op": 2,
            "d": [
                "token": token,
                "capabilities": 16381,
                "properties": [
                    "os": "iOS",
                    "browser": "Discord iOS",
                    "device": "iPhone15,3"
                ],
                "presence": presence
            ]
        ]
        sendJSON(payload)
    }

    public func updateStatus(desc: String) {
        self.currentDesc = desc
        if isIdentified {
            sendPresenceUpdate()
        }
    }

    private func sendPresenceUpdate() {
        let payload: [String: Any] = [
            "op": 3,
            "d": [
                "since": 0,
                "activities": [buildActivity()],
                "status": "online",
                "afk": false
            ]
        ]
        sendJSON(payload)
    }

    private func buildActivity() -> [String: Any] {
        var act: [String: Any] = [
            "name": gameName.isEmpty ? "Nintendo Switch" : gameName,
            "type": 0, // Playing
            "application_id": "701019662778155068",
            "timestamps": ["start": startTime * 1000]
        ]
        if !currentDesc.isEmpty {
            act["details"] = currentDesc
        }
        let cleanId = gameId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !cleanId.isEmpty {
            act["state"] = cleanId
            let imageURL: String
            if let cEnv = getenv("DM_DISCORD_IMAGE"), let sEnv = String(validatingUTF8: cEnv), !sEnv.isEmpty {
                imageURL = sEnv
            } else if let customImg = ProcessInfo.processInfo.environment["DM_DISCORD_IMAGE"], !customImg.isEmpty {
                imageURL = customImg
            } else {
                // Direct CDN artwork URL ending in .jpg (required by Discord Media Proxy)
                imageURL = "https://raw.githubusercontent.com/n1cknam3l3ss/nxnative/main/dm/games/\(cleanId)/icon.jpg"
            }
            act["assets"] = [
                "large_image": imageURL,
                "large_text": gameName.isEmpty ? "Nintendo Switch" : gameName
            ]
        }
        return act
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(str)) { error in
            if let e = error {
                fputs("[discord-gateway] send error: \(e.localizedDescription)\n", stderr)
            }
        }
    }

    public func stop() {
        if isIdentified {
            let clearPayload: [String: Any] = [
                "op": 3,
                "d": [
                    "since": 0,
                    "activities": [] as [Any],
                    "status": "online",
                    "afk": false
                ]
            ]
            sendJSON(clearPayload)
        }
        DispatchQueue.main.async { [weak self] in
            self?.heartbeatTimer?.invalidate()
            self?.heartbeatTimer = nil
        }
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isIdentified = false
    }

    private func reconnect(token: String) {
        stop()
        DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.connect(token: token)
        }
    }

    public static func fetchUserProfile(token: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://discord.com/api/v9/users/@me") else {
            completion(nil); return
        }
        var req = URLRequest(url: url)
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.setValue("Discord iOS", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil); return
            }
            let username = (json["global_name"] as? String) ?? (json["username"] as? String)
            completion(username)
        }.resume()
    }
}

// C-exported interfaces for dm/host/hle_discord.c
@_cdecl("dm_discord_ios_start")
public func dm_discord_ios_start(name: UnsafePointer<CChar>?, id: UnsafePointer<CChar>?) {
    let gname = name != nil ? String(cString: name!) : ""
    let gid = id != nil ? String(cString: id!) : ""
    DiscordGateway.shared.start(gameName: gname, gameId: gid)
}

@_cdecl("dm_discord_ios_set_status")
public func dm_discord_ios_set_status(status: UnsafePointer<CChar>?) {
    let s = status != nil ? String(cString: status!) : ""
    DiscordGateway.shared.updateStatus(desc: s)
}

@_cdecl("dm_discord_ios_stop")
public func dm_discord_ios_stop() {
    DiscordGateway.shared.stop()
}

@_cdecl("dm_discord_ios_has_token")
public func dm_discord_ios_has_token() -> Bool {
    guard let token = UserDefaults.standard.string(forKey: "discord_token"), !token.isEmpty else {
        return false
    }
    return true
}

// SwiftUI Discord Login Views
public struct DiscordLoginSheet: View {
    @Binding var isPresented: Bool
    let onLoggedIn: (String, String) -> Void
    @State private var loading = true

    public init(isPresented: Binding<Bool>, onLoggedIn: @escaping (String, String) -> Void) {
        self._isPresented = isPresented
        self.onLoggedIn = onLoggedIn
    }

    public var body: some View {
        NavigationView {
            ZStack {
                DiscordWebView(onTokenExtracted: { token in
                    DiscordGateway.fetchUserProfile(token: token) { username in
                        DispatchQueue.main.async {
                            onLoggedIn(token, username ?? "User")
                            isPresented = false
                        }
                    }
                }, onLoadingChanged: { isLoading in
                    loading = isLoading
                })
                if loading {
                    ProgressView("Connecting to Discord…")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
            }
            .navigationTitle("Discord Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}

public struct DiscordWebView: UIViewRepresentable {
    let onTokenExtracted: (String) -> Void
    let onLoadingChanged: (Bool) -> Void

    public init(onTokenExtracted: @escaping (String) -> Void, onLoadingChanged: @escaping (Bool) -> Void) {
        self.onTokenExtracted = onTokenExtracted
        self.onLoadingChanged = onLoadingChanged
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onTokenExtracted: onTokenExtracted, onLoadingChanged: onLoadingChanged)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "discordAuth")

        // Intercept XMLHttpRequest, fetch, and webpackChunkdiscord_app
        let scriptSource = """
        (function() {
            function checkToken(val) {
                if (typeof val === 'string' && val.length > 30 && !val.startsWith('Bot ') && val.indexOf('.') !== -1) {
                    window.webkit.messageHandlers.discordAuth.postMessage(val);
                }
            }
            var origSetHeader = XMLHttpRequest.prototype.setRequestHeader;
            XMLHttpRequest.prototype.setRequestHeader = function(h, v) {
                if (h && h.toLowerCase() === 'authorization') checkToken(v);
                return origSetHeader.apply(this, arguments);
            };
            var origFetch = window.fetch;
            window.fetch = function() {
                var args = arguments;
                if (args[1] && args[1].headers) {
                    var h = args[1].headers;
                    var auth = h['Authorization'] || h['authorization'];
                    if (auth) checkToken(auth);
                }
                return origFetch.apply(this, args).then(function(res) {
                    if (res && res.url) {
                        if (res.url.indexOf('/api/v9/auth/login') !== -1 || res.url.indexOf('/api/v9/auth/mfa') !== -1) {
                            try {
                                res.clone().json().then(function(data) {
                                    if (data && data.token) checkToken(data.token);
                                });
                            } catch(e) {}
                        }
                    }
                    return res;
                });
            };
            var tokenFound = false;
            function pollWebpack() {
                if (tokenFound) return;
                try {
                    if (window.webpackChunkdiscord_app) {
                        var m = [];
                        window.webpackChunkdiscord_app.push([['__probe__'], {}, function(e) {
                            for (var c in e.c) m.push(e.c[c]);
                        }]);
                        for (var i = 0; i < m.length; i++) {
                            var exp = m[i] && m[i].exports;
                            if (exp && exp.default && typeof exp.default.getToken === 'function') {
                                var t = exp.default.getToken();
                                if (t) {
                                    tokenFound = true;
                                    checkToken(t);
                                    return;
                                }
                            }
                        }
                    }
                } catch(e) {}
                setTimeout(pollWebpack, 1000);
            }
            setTimeout(pollWebpack, 1500);
        })();
        """
        let userScript = WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(userScript)

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        if let url = URL(string: "https://discord.com/login") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}

    public final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onTokenExtracted: (String) -> Void
        let onLoadingChanged: (Bool) -> Void
        private var handled = false

        init(onTokenExtracted: @escaping (String) -> Void, onLoadingChanged: @escaping (Bool) -> Void) {
            self.onTokenExtracted = onTokenExtracted
            self.onLoadingChanged = onLoadingChanged
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "discordAuth",
                  let token = message.body as? String,
                  !handled else { return }
            let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanToken.count > 30 {
                handled = true
                onTokenExtracted(cleanToken)
            }
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoadingChanged(false)
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onLoadingChanged(false)
        }
    }
}
