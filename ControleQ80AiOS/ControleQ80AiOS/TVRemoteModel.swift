import Foundation
import Combine

enum ConnectionState: Equatable {
    case disconnected, connecting, authorization, connected, reconnecting, timeout
}

@MainActor
final class TVRemoteModel: ObservableObject {
    @Published private(set) var settings = LocalStore.load()
    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var status = "Conecte à TV na rede local."
    @Published private(set) var apps: [TVApp] = []
    @Published private(set) var hasPairing = false

    private var activeIP = ""
    private var session: URLSession?
    private var delegate: TVSessionDelegate?
    private var socket: URLSessionWebSocketTask?
    private var appTask: URLSessionDataTask?
    private var generation = 0
    private var everConnected = false
    private var retries = 0
    private var timeoutWork: DispatchWorkItem?
    private var reconnectWork: DispatchWorkItem?
    private var volumeWork: DispatchWorkItem?
    private var pendingVolume = 0
    private var waitingForApps = false

    init() {
        hasPairing = PairingStore.token(for: settings.ip) != nil
    }

    func connectIfNeeded() {
        if state == .disconnected || state == .timeout { connect(to: settings.ip) }
    }

    func save(_ value: TVSettings) -> Bool {
        guard TVProtocol.isPrivateIPv4(value.ip),
              [value.spotifyID, value.youtubeID, value.netflixID].allSatisfy({
                  $0.isEmpty || TVProtocol.isValidAppID($0)
              }) else {
            status = "Confira o IP e os IDs dos aplicativos."
            return false
        }
        do {
            try LocalStore.save(value)
            if settings.ip != value.ip {
                PairingStore.clear(for: settings.ip)
                apps = []
            }
            settings = value
            hasPairing = PairingStore.token(for: value.ip) != nil
            status = "Configurações salvas neste iPhone."
            return true
        } catch {
            status = "Não foi possível salvar as configurações locais."
            return false
        }
    }

    func connect(to ip: String) {
        guard TVProtocol.isPrivateIPv4(ip) else {
            status = "Informe um IPv4 privado válido."
            return
        }
        disconnect()
        activeIP = ip
        everConnected = false
        retries = 0
        hasPairing = PairingStore.token(for: ip) != nil
        startConnection()
    }

    private func startConnection() {
        guard let url = TVProtocol.webSocketURL(ip: activeIP, token: PairingStore.token(for: activeIP)) else {
            state = .disconnected
            status = "IP inválido."
            return
        }
        generation += 1
        let id = generation
        state = retries > 0 ? .reconnecting : .connecting
        status = retries > 0 ? "Reconectando à TV (\(retries)/3)…" : "Conectando à TV…"
        let tvDelegate = TVSessionDelegate(host: activeIP)
        tvDelegate.onOpen = { [weak self] in
            Task { @MainActor in self?.opened(id: id) }
        }
        tvDelegate.onClose = { [weak self] in
            Task { @MainActor in self?.lostConnection(id: id, timedOut: false) }
        }
        delegate = tvDelegate
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let newSession = URLSession(configuration: configuration, delegate: tvDelegate, delegateQueue: nil)
        session = newSession
        let task = newSession.webSocketTask(with: url)
        socket = task
        task.resume()
        receive(id: id)
        armTimeout(seconds: 8, id: id, expected: .connecting)
    }

    private func opened(id: Int) {
        guard id == generation, state != .connected else { return }
        state = .authorization
        status = "Aguardando autorização. Aceite na TV, se aparecer."
        armTimeout(seconds: 25, id: id, expected: .authorization)
    }

    private func receive(id: Int) {
        socket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self, id == self.generation else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text): self.handle(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) { self.handle(text) }
                    @unknown default: break
                    }
                    self.receive(id: id)
                case .failure:
                    self.lostConnection(id: id, timedOut: false)
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let event = object["event"] as? String else { return }
        switch event {
        case "ms.channel.connect":
            let data = object["data"] as? [String: Any] ?? [:]
            let clients = data["clients"] as? [[String: Any]] ?? []
            let received = (data["token"] as? String) ??
                clients.compactMap { ($0["attributes"] as? [String: Any])?["token"] as? String }.first
            if let received, !received.isEmpty {
                hasPairing = PairingStore.saveToken(received, for: activeIP)
            }
            cancelTimeout()
            everConnected = true
            retries = 0
            state = .connected
            status = hasPairing ? "Conectado à TV. Pareamento salvo." : "Conectado à TV."
            requestApps()
        case "ms.channel.unauthorized":
            state = .authorization
            status = "Autorização pendente ou recusada na TV."
            armTimeout(seconds: 25, id: generation, expected: .authorization)
        case "ms.channel.disconnect":
            lostConnection(id: generation, timedOut: false)
        case "ms.channel.timeOut":
            lostConnection(id: generation, timedOut: true)
        case "ed.installedApp.get":
            waitingForApps = false
            if let payload = object["data"] as? [String: Any],
               let items = payload["data"] as? [[String: Any]] {
                apps = items.compactMap { item in
                    guard let id = item["appId"] as? String, TVProtocol.isValidAppID(id) else { return nil }
                    return TVApp(id: id, name: (item["name"] as? String) ?? id)
                }
                status = apps.isEmpty ? "A TV não informou apps instalados." : "\(apps.count) apps informados pela TV."
            }
        default:
            break
        }
    }

    private func armTimeout(seconds: Double, id: Int, expected: ConnectionState) {
        cancelTimeout()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == id, self.state == expected else { return }
                self.lostConnection(id: id, timedOut: true)
            }
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelTimeout() {
        timeoutWork?.cancel()
        timeoutWork = nil
    }

    private func lostConnection(id: Int, timedOut: Bool) {
        guard id == generation else { return }
        generation += 1
        let nextId = generation
        closeConnection()
        if everConnected && retries < 3 {
            retries += 1
            state = .reconnecting
            status = "Conexão perdida; reconectando (\(retries)/3)…"
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self, self.generation == nextId else { return }
                    self.startConnection()
                }
            }
            reconnectWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(1 << retries), execute: work)
        } else {
            state = timedOut ? .timeout : .disconnected
            status = timedOut ? "Tempo esgotado. Confira a TV e tente novamente." :
                "TV desconectada. Confira Wi-Fi, IP e autorização."
        }
    }

    private func closeConnection() {
        cancelTimeout()
        waitingForApps = false
        pendingVolume = 0
        volumeWork?.cancel()
        volumeWork = nil
        appTask?.cancel()
        appTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
        delegate = nil
    }

    func disconnect() {
        generation += 1
        reconnectWork?.cancel()
        reconnectWork = nil
        closeConnection()
        everConnected = false
        retries = 0
        state = .disconnected
        status = "Desconectado."
    }

    func clearPairing() {
        PairingStore.clear(for: settings.ip)
        hasPairing = false
        disconnect()
        status = "Token e certificado local apagados. Autorize novamente na TV."
    }

    private func send(_ value: String?) {
        guard state == .connected, let value, let socket else {
            status = "Conecte à TV primeiro."
            return
        }
        socket.send(.string(value)) { [weak self] error in
            if error != nil {
                Task { @MainActor in self?.status = "Comando não enviado. Reconecte a TV." }
            }
        }
    }

    func sendKey(_ key: String) { send(TVProtocol.key(key)) }

    func sendText(_ value: String) {
        guard !value.isEmpty else { return }
        send(TVProtocol.text(value))
        if state == .connected { status = "Texto enviado; confirme na TV. O firmware pode ignorá-lo." }
    }

    func requestApps() {
        guard state == .connected else {
            status = "Conecte à TV para consultar os aplicativos."
            return
        }
        waitingForApps = true
        send(TVProtocol.appListRequest())
        status = "Consultando apps instalados…"
        let id = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == id, self.waitingForApps else { return }
                self.waitingForApps = false
                self.status = "A TV não informou os apps. Use os IDs salvos ou edite-os."
            }
        }
    }

    func adjustVolume(_ clicks: Int) {
        guard clicks != 0 else { return }
        guard state == .connected else {
            status = "Conecte à TV antes de ajustar o volume."
            return
        }
        pendingVolume = min(20, max(-20, pendingVolume + clicks))
        if volumeWork == nil { drainVolume() }
    }

    private func drainVolume() {
        guard state == .connected, pendingVolume != 0 else {
            pendingVolume = 0
            volumeWork = nil
            return
        }
        let direction = pendingVolume > 0 ? 1 : -1
        pendingVolume -= direction
        sendKey(direction > 0 ? "KEY_VOLUP" : "KEY_VOLDOWN")
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.drainVolume() }
        }
        volumeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func launchApp(_ id: String) {
        guard state == .connected,
              let url = TVProtocol.appURL(ip: activeIP, id: id),
              let session else {
            status = "Conecte à TV e configure um ID válido."
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data()
        let currentId = generation
        appTask = session.dataTask(with: request) { [weak self] _, response, error in
            Task { @MainActor in
                guard let self, self.generation == currentId else { return }
                self.appTask = nil
                if error != nil {
                    self.status = "Falha ao abrir app pela API local. Tente pelo menu da TV."
                } else if let response = response as? HTTPURLResponse {
                    self.status = (200...299).contains(response.statusCode) ?
                        "Abertura solicitada; confirme na TV." :
                        "TV recusou a abertura (HTTP \(response.statusCode))."
                }
            }
        }
        appTask?.resume()
    }
}
