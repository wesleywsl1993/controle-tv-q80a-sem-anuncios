import SwiftUI

private let background = Color(red: 0.03, green: 0.04, blue: 0.07)
private let panel = Color(red: 0.08, green: 0.11, blue: 0.16)
private let accent = Color(red: 0.47, green: 0.66, blue: 1.0)

@MainActor
struct ContentView: View {
    @ObservedObject var model: TVRemoteModel
    @State private var showSettings = false
    @State private var showKeyboard = false
    @State private var volumeGesture = 10.0
    @State private var lastVolumeStep = 10

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CONTROLE Q80A").font(.title3.bold()).tracking(1)
                        Text("Samsung QLED · rede local · sem anúncios")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill").font(.title3)
                            .frame(width: 48, height: 48)
                    }
                    .accessibilityLabel("Configurações")
                }

                HStack(spacing: 8) {
                    appButton("Spotify", id: model.settings.spotifyID, symbol: "music.note")
                    appButton("YouTube", id: model.settings.youtubeID, symbol: "play.rectangle.fill")
                    appButton("Netflix", id: model.settings.netflixID, symbol: "play.tv.fill")
                }

                HStack(spacing: 8) {
                    tile("Ligar / desligar", symbol: "power") { model.sendKey("KEY_POWER") }
                    tile("Início", symbol: "house.fill") { model.sendKey("KEY_HOME") }
                    tile("Teclado", symbol: "keyboard") { showKeyboard = true }
                }

                VStack(spacing: 8) {
                    direction("↑", label: "Cima", key: "KEY_UP")
                    HStack(spacing: 12) {
                        direction("←", label: "Esquerda", key: "KEY_LEFT")
                        Button("OK") { model.sendKey("KEY_ENTER") }
                            .font(.title3.bold()).foregroundStyle(background)
                            .frame(width: 84, height: 84)
                            .background(accent, in: Circle())
                            .accessibilityLabel("OK")
                        direction("→", label: "Direita", key: "KEY_RIGHT")
                    }
                    direction("↓", label: "Baixo", key: "KEY_DOWN")
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    tile("Voltar", symbol: "arrow.uturn.backward") { model.sendKey("KEY_RETURN") }
                    tile("Mudo", symbol: "speaker.slash.fill") { model.sendKey("KEY_MUTE") }
                    tile("Menu", symbol: "list.bullet") { model.sendKey("KEY_MENU") }
                }

                VStack(spacing: 2) {
                    HStack {
                        Button { model.sendKey("KEY_VOLDOWN") } label: {
                            Image(systemName: "speaker.minus.fill").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Diminuir volume")
                        Slider(
                            value: Binding(
                                get: { volumeGesture },
                                set: { value in
                                    let step = min(20, max(0, Int(value.rounded())))
                                    let delta = step - lastVolumeStep
                                    volumeGesture = Double(step)
                                    if delta != 0 {
                                        lastVolumeStep = step
                                        model.adjustVolume(delta)
                                    }
                                }
                            ),
                            in: 0...20,
                            step: 1,
                            onEditingChanged: { editing in
                                if !editing {
                                    volumeGesture = 10
                                    lastVolumeStep = 10
                                }
                            }
                        )
                        .tint(accent)
                        .accessibilityLabel("Volume relativo")
                        .accessibilityHint("Arraste à esquerda para diminuir ou à direita para aumentar")
                        Button { model.sendKey("KEY_VOLUP") } label: {
                            Image(systemName: "speaker.plus.fill").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Aumentar volume")
                    }
                    Text("Arraste para ajustar. O centro não é o volume atual da TV.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    smallKey("Canal −", "KEY_CHDOWN")
                    smallKey("Canal +", "KEY_CHUP")
                    smallKey("▶", "KEY_PLAY")
                    smallKey("Ⅱ", "KEY_PAUSE")
                }
                HStack(spacing: 8) {
                    smallKey("⏪", "KEY_REWIND")
                    smallKey("⏩", "KEY_FF")
                    smallKey("■", "KEY_STOP")
                }

                Text(model.status)
                    .font(.footnote)
                    .foregroundStyle(model.state == .connected ? accent : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            .padding(18)
        }
        .background(background.ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        .sheet(isPresented: $showKeyboard) { KeyboardView(model: model) }
        .task { model.connectIfNeeded() }
    }

    private func appButton(_ title: String, id: String, symbol: String) -> some View {
        Button { model.launchApp(id) } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3).foregroundStyle(accent)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity).frame(height: 66)
            .background(panel, in: RoundedRectangle(cornerRadius: 16))
        }
        .disabled(id.isEmpty)
    }

    private func tile(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).frame(height: 62)
            .background(panel, in: RoundedRectangle(cornerRadius: 15))
        }
        .accessibilityLabel(title)
    }

    private func direction(_ symbol: String, label: String, key: String) -> some View {
        Button { model.sendKey(key) } label: {
            Text(symbol).font(.system(size: 28, weight: .light))
                .frame(width: 68, height: 68)
                .background(panel, in: Circle())
        }
        .accessibilityLabel(label)
    }

    private func smallKey(_ title: String, _ key: String) -> some View {
        Button(title) { model.sendKey(key) }
            .font(.subheadline)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(panel, in: RoundedRectangle(cornerRadius: 12))
    }
}

@MainActor
private struct SettingsView: View {
    @ObservedObject var model: TVRemoteModel
    @Environment(\.dismiss) private var dismiss
    @State private var ip: String
    @State private var spotifyID: String
    @State private var youtubeID: String
    @State private var netflixID: String

    init(model: TVRemoteModel) {
        self.model = model
        _ip = State(initialValue: model.settings.ip)
        _spotifyID = State(initialValue: model.settings.spotifyID)
        _youtubeID = State(initialValue: model.settings.youtubeID)
        _netflixID = State(initialValue: model.settings.netflixID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("TV na mesma rede Wi-Fi") {
                    TextField("IP da TV", text: $ip)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Testar conexão sem salvar") { model.connect(to: ip.trimmingCharacters(in: .whitespaces)) }
                    Button("Consultar apps instalados") { model.requestApps() }
                    Text(model.status).font(.footnote)
                    Text("No iPhone, informe o IP manualmente. A descoberta SSDP exige uma autorização especial da Apple.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !model.apps.isEmpty {
                    Section("Apps informados pela TV") {
                        ForEach(model.apps.filter {
                            ["spotify", "youtube", "netflix"].contains(where: { name in
                                $0.name.localizedCaseInsensitiveContains(name)
                            })
                        }) { app in
                            Button("\(app.name): \(app.id)") {
                                if app.name.localizedCaseInsensitiveContains("spotify") { spotifyID = app.id }
                                else if app.name.localizedCaseInsensitiveContains("youtube") { youtubeID = app.id }
                                else if app.name.localizedCaseInsensitiveContains("netflix") { netflixID = app.id }
                            }
                        }
                    }
                }
                Section("IDs dos aplicativos") {
                    TextField("Spotify", text: $spotifyID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("YouTube", text: $youtubeID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Netflix", text: $netflixID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Preencher IDs informados para esta TV") {
                        spotifyID = "201606009684"
                        youtubeID = "111299001912"
                        netflixID = "3201907018807"
                    }
                }
                Section("Privacidade") {
                    Text("IP salvo: \(model.settings.ip)")
                    Text("Pareamento salvo: \(model.hasPairing ? "sim" : "não")")
                    Button("Limpar token e certificado", role: .destructive) { model.clearPairing() }
                    Text("Token no Keychain deste iPhone; IP e IDs em arquivo local excluído do backup.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Configurações")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Voltar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salvar e conectar") {
                        let candidate = TVSettings(
                            ip: ip.trimmingCharacters(in: .whitespaces),
                            spotifyID: spotifyID.trimmingCharacters(in: .whitespaces),
                            youtubeID: youtubeID.trimmingCharacters(in: .whitespaces),
                            netflixID: netflixID.trimmingCharacters(in: .whitespaces)
                        )
                        if model.save(candidate) { model.connect(to: candidate.ip) }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

@MainActor
private struct KeyboardView: View {
    @ObservedObject var model: TVRemoteModel
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""

    var body: some View {
        NavigationStack {
            Form {
                Text("Abra um campo de busca na TV. Se o texto não aparecer, use as setas e OK no teclado da TV.")
                    .font(.footnote)
                TextField("Texto para a TV", text: $value)
                    .textInputAutocapitalization(.never)
                Button("Enviar") {
                    model.sendText(value)
                    dismiss()
                }
                .disabled(value.isEmpty)
            }
            .navigationTitle("Teclado")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Fechar") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
