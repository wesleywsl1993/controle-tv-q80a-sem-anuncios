package br.com.wesley.controleq80a

import org.json.JSONObject
import java.util.Base64
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl

/** Accept only literal private IPv4 addresses; no DNS or URL input can leave the LAN. */
object TvProtocol {
    /** OkHttp's WebSocket handshake takes an HTTP(S) URL and upgrades it to WS(S). */
    fun remoteUrl(ip: String, secure: Boolean, token: String): HttpUrl {
        require(validIp(ip)) { "IP inválido" }
        val scheme = if (secure) "https" else "http"
        return "$scheme://$ip:${if (secure) 8002 else 8001}/api/v2/channels/samsung.remote.control"
            .toHttpUrl().newBuilder()
            .addQueryParameter("name", Base64.getEncoder().encodeToString("Controle Q80A".toByteArray(Charsets.UTF_8)))
            .apply { if (token.isNotBlank()) addQueryParameter("token", token) }
            .build()
    }

    fun validIp(value: String): Boolean {
        val parts = value.split('.')
        if (parts.size != 4 || parts.any { it.isEmpty() || it.length > 3 || it.any { c -> !c.isDigit() } }) return false
        val bytes = parts.map { it.toIntOrNull() ?: return false }
        if (bytes.any { it !in 0..255 }) return false
        return bytes[0] == 10 ||
            (bytes[0] == 172 && bytes[1] in 16..31) ||
            (bytes[0] == 192 && bytes[1] == 168)
    }

    fun validAppId(value: String): Boolean =
        value.length in 1..80 && value.all { it in 'a'..'z' || it in 'A'..'Z' ||
            it in '0'..'9' || it == '.' || it == '_' || it == '-' }

    fun key(value: String): String = JSONObject()
        .put("method", "ms.remote.control")
        .put("params", JSONObject().put("Cmd", "Click").put("DataOfCmd", value)
            .put("Option", "false").put("TypeOfRemote", "SendRemoteKey"))
        .toString()

    fun text(value: String): String = JSONObject()
        .put("method", "ms.remote.control")
        .put("params", JSONObject().put("Cmd", Base64.getEncoder().encodeToString(value.toByteArray(Charsets.UTF_8)))
            .put("DataOfCmd", "base64").put("TypeOfRemote", "SendInputString"))
        .toString()

    fun appListRequest(): String = JSONObject().put("method", "ms.channel.emit")
        .put("params", JSONObject().put("event", "ed.installedApp.get").put("to", "host")).toString()
}
