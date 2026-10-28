package br.com.wesley.controleq80a

import android.os.Handler
import android.os.Looper
import okhttp3.*
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.net.*
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.*

enum class TvState { DISCONNECTED, CONNECTING, AUTH_PENDING, CONNECTED, RECONNECTING, TIMEOUT }
data class TvApp(val name: String, val id: String)

/** Connection state and callbacks stay on the main thread. */
class TvRemoteClient(
    private val onState: (TvState, String) -> Unit,
    private val onToken: (String) -> Unit,
    private val onApps: (List<TvApp>) -> Unit
) {
    private val main = Handler(Looper.getMainLooper())
    private var socket: WebSocket? = null
    private var discoverySocket: DatagramSocket? = null
    private val calls = mutableSetOf<Call>()
    private var ip = ""
    private var token = ""
    private var state = TvState.DISCONNECTED
    private var generation = 0
    private var retries = 0
    private var connectedOnce = false
    private var timeout: Runnable? = null
    private var reconnect: Runnable? = null
    private var waitingForApps = false
    private var pendingVolumeClicks = 0
    private var volumeRunner: Runnable? = null

    // Only the WSS client below trusts the TV's self-signed certificate.
    // It is used solely for the validated private IPv4 endpoint, with no redirects.
    private val tvTrust = object : X509TrustManager {
        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
            require(!chain.isNullOrEmpty()) { "Certificado da TV ausente" }
            chain[0].checkValidity()
        }
    }
    private val secureClient: OkHttpClient by lazy {
        val ssl = SSLContext.getInstance("TLS")
        ssl.init(null, arrayOf<TrustManager>(tvTrust), SecureRandom())
        OkHttpClient.Builder().sslSocketFactory(ssl.socketFactory, tvTrust)
            .hostnameVerifier { host, _ -> host == ip && TvProtocol.validIp(host) }
            .followRedirects(false).followSslRedirects(false)
            .connectTimeout(8, TimeUnit.SECONDS).readTimeout(0, TimeUnit.SECONDS)
            .pingInterval(15, TimeUnit.SECONDS).build()
    }
    private val localClient = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false)
        .connectTimeout(8, TimeUnit.SECONDS).callTimeout(10, TimeUnit.SECONDS).build()

    fun connect(tvIp: String, savedToken: String = "") {
        disconnect()
        if (!TvProtocol.validIp(tvIp)) {
            setState(TvState.DISCONNECTED, "Informe um IPv4 privado válido da TV.")
            return
        }
        ip = tvIp
        token = savedToken
        retries = 0
        connectedOnce = false
        openSocket(false)
    }

    private fun openSocket(fallback: Boolean) {
        val id = ++generation
        try {
        val url = TvProtocol.remoteUrl(ip, !fallback, token)
        setState(if (retries > 0) TvState.RECONNECTING else TvState.CONNECTING,
            if (fallback) "Porta segura indisponível; tentando conexão local sem TLS…" else "Conectando à TV…")
        socket = (if (fallback) localClient else secureClient).newWebSocket(Request.Builder().url(url).build(),
            object : WebSocketListener() {
                private var opened = false
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    opened = true
                    onMain(id) {
                        setState(TvState.AUTH_PENDING, "Aguardando autorização. Aceite na TV, se aparecer.")
                        armTimeout(id, 25_000)
                    }
                }
                override fun onMessage(webSocket: WebSocket, text: String) = onMain(id) {
                    val json = try { JSONObject(text) } catch (_: Exception) { return@onMain }
                    when (json.optString("event")) {
                        "ms.channel.connect" -> {
                            val data = json.optJSONObject("data")
                            val clients = data?.optJSONArray("clients")
                            val received = data?.optString("token").orEmpty().ifBlank {
                                (0 until (clients?.length() ?: 0)).asSequence().mapNotNull {
                                    clients?.optJSONObject(it)?.optJSONObject("attributes")?.optString("token")
                                }.firstOrNull { it.isNotBlank() }.orEmpty()
                            }
                            if (received.isNotBlank()) { token = received; onToken(received) }
                            cancelTimeout()
                            retries = 0
                            connectedOnce = true
                            setState(TvState.CONNECTED, "Conectado à TV")
                            requestApps()
                        }
                        "ms.channel.unauthorized" -> {
                            setState(TvState.AUTH_PENDING, "Autorização pendente ou recusada na TV.")
                            armTimeout(id, 25_000)
                        }
                        "ms.channel.disconnect" -> { webSocket.cancel(); failed(id, connectedOnce, false) }
                        "ms.channel.timeOut" -> { webSocket.cancel(); failed(id, false, true) }
                        "ed.installedApp.get" -> {
                            waitingForApps = false
                            val list = json.optJSONObject("data")?.optJSONArray("data")
                            if (list != null) onApps((0 until list.length()).mapNotNull { index ->
                                val app = list.optJSONObject(index) ?: return@mapNotNull null
                                val appId = app.optString("appId")
                                if (TvProtocol.validAppId(appId)) TvApp(app.optString("name", appId), appId) else null
                            })
                        }
                    }
                }
                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) = onMain(id) {
                    if (!fallback && !opened && response == null && (t is ConnectException || t is SocketTimeoutException)) {
                        webSocket.cancel()
                        openSocket(true)
                    } else failed(id, response == null && t !is SSLException, t is SocketTimeoutException)
                }
                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) = onMain(id) {
                    failed(id, connectedOnce, false)
                }
            })
        armTimeout(id, 8_000)
        } catch (_: Exception) { failed(id, false, false) }
    }

    private fun failed(id: Int, mayRetry: Boolean, timedOut: Boolean) {
        if (id != generation || reconnect != null) return
        cancelTimeout()
        socket?.cancel(); socket = null
        waitingForApps = false
        pendingVolumeClicks = 0
        volumeRunner?.let(main::removeCallbacks); volumeRunner = null
        if (mayRetry) {
            retries = (retries + 1).coerceAtMost(5)
            val delay = (1L shl retries).coerceAtMost(30) * 1_000L
            setState(TvState.RECONNECTING, "Conexão perdida. Nova tentativa em ${delay / 1_000}s…")
            reconnect = Runnable { reconnect = null; openSocket(false) }.also {
                main.postDelayed(it, delay)
            }
        } else setState(if (timedOut) TvState.TIMEOUT else TvState.DISCONNECTED,
            if (timedOut) "Tempo esgotado. Confira a TV e tente reconectar."
            else "TV desconectada. Confira IP, Wi-Fi e autorização.")
    }
    private fun armTimeout(id: Int, millis: Long) {
        cancelTimeout()
        timeout = Runnable {
            if (id == generation && state != TvState.CONNECTED)
                failed(id, state != TvState.AUTH_PENDING, true)
        }
        main.postDelayed(timeout!!, millis)
    }
    private fun cancelTimeout() { timeout?.let(main::removeCallbacks); timeout = null }
    private fun onMain(id: Int, action: () -> Unit) { main.post { if (id == generation) action() } }
    private fun setState(value: TvState, message: String) { state = value; onState(value, message) }

    private fun reconnectIfNeeded() {
        if ((state == TvState.DISCONNECTED || state == TvState.TIMEOUT) && TvProtocol.validIp(ip))
            connect(ip, token)
    }

    fun sendKey(key: String) {
        if (state != TvState.CONNECTED) {
            reconnectIfNeeded()
            setState(state, "Comando não enviado. Aguarde a conexão e tente novamente.")
        } else if (socket?.send(TvProtocol.key(key)) != true) failed(generation, true, false)
    }
    /** A slider gesture is relative: the TV does not report an absolute volume level. */
    fun adjustVolume(clicks: Int) {
        if (clicks == 0) return
        if (state != TvState.CONNECTED) {
            reconnectIfNeeded()
            setState(state, "Aguarde a conexão para ajustar o volume.")
            return
        }
        pendingVolumeClicks = (pendingVolumeClicks + clicks).coerceIn(-20, 20)
        if (volumeRunner != null) return
        volumeRunner = object : Runnable {
            override fun run() {
                if (state != TvState.CONNECTED || pendingVolumeClicks == 0) {
                    pendingVolumeClicks = 0
                    volumeRunner = null
                    return
                }
                val direction = if (pendingVolumeClicks > 0) 1 else -1
                pendingVolumeClicks -= direction
                val key = if (direction > 0) "KEY_VOLUP" else "KEY_VOLDOWN"
                if (socket?.send(TvProtocol.key(key)) != true) {
                    pendingVolumeClicks = 0
                    volumeRunner = null
                    failed(generation, true, false)
                    return
                }
                main.postDelayed(this, 120)
            }
        }.also(main::post)
    }
    fun sendText(value: String) {
        if (value.isBlank()) return
        if (state != TvState.CONNECTED) {
            reconnectIfNeeded()
            setState(state, "Texto não enviado. Aguarde a conexão e tente novamente.")
        } else if (socket?.send(TvProtocol.text(value)) != true) failed(generation, true, false)
        else setState(state, "Texto enviado; confirme na TV. O firmware pode ignorá-lo.")
    }
    fun requestApps() {
        if (state != TvState.CONNECTED) {
            reconnectIfNeeded()
            setState(state, "Aguarde a conexão para consultar os aplicativos.")
        } else if (socket?.send(TvProtocol.appListRequest()) != true) failed(generation, true, false)
        else {
            waitingForApps = true
            val id = generation
            setState(state, "Consultando apps instalados; aguarde a resposta da TV…")
            main.postDelayed({
                if (id == generation && waitingForApps) {
                    waitingForApps = false
                    setState(state, "A TV não informou os apps. Use IDs de referência ou informe-os manualmente.")
                }
            }, 6_000)
        }
    }
    fun launchApp(appId: String) {
        if (state != TvState.CONNECTED || !TvProtocol.validAppId(appId)) {
            reconnectIfNeeded()
            setState(state, "Conecte a TV e configure um ID de aplicativo válido."); return
        }
        val request = Request.Builder().url("http://$ip:8001/api/v2/applications/$appId")
            .post(ByteArray(0).toRequestBody()).build()
        val call = localClient.newCall(request)
        calls += call
        val id = generation
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) = onMain(id) {
                calls -= call
                setState(state, "Falha ao abrir app pela API local. Tente pelo menu da TV.")
            }
            override fun onResponse(call: Call, response: Response) {
                val result = response.use {
                    if (it.isSuccessful) "Abertura solicitada; confirme na TV."
                    else "TV recusou a abertura (HTTP ${it.code})."
                }
                onMain(id) { calls -= call; setState(state, result) }
            }
        })
    }
    /** User-triggered SSDP only. Never follows LOCATION or contacts a discovered host. */
    fun discover(onFound: (String) -> Unit) {
        Thread {
            try {
                DatagramSocket().use { udp ->
                    discoverySocket = udp
                    udp.soTimeout = 2_000
                    val query = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: ssdp:all\r\n\r\n".toByteArray()
                    udp.send(DatagramPacket(query, query.size, InetAddress.getByName("239.255.255.250"), 1900))
                    val until = System.currentTimeMillis() + 3_000
                    while (System.currentTimeMillis() < until) {
                        val packet = DatagramPacket(ByteArray(2048), 2048)
                        try { udp.receive(packet) } catch (_: SocketTimeoutException) { break }
                        val address = packet.address.hostAddress ?: continue
                        val data = String(packet.data, 0, packet.length)
                        if (TvProtocol.validIp(address) && data.contains("Samsung", true))
                            main.post { onFound(address) }
                    }
                }
            } catch (_: Exception) { /* Manual IP remains available. */ }
            finally { discoverySocket = null }
        }.start()
    }
    fun disconnect() {
        generation++
        waitingForApps = false
        pendingVolumeClicks = 0
        volumeRunner?.let(main::removeCallbacks); volumeRunner = null
        cancelTimeout()
        reconnect?.let(main::removeCallbacks); reconnect = null
        socket?.cancel(); socket = null
        calls.forEach(Call::cancel); calls.clear()
        discoverySocket?.close(); discoverySocket = null
        setState(TvState.DISCONNECTED, "Desconectado")
    }
}
