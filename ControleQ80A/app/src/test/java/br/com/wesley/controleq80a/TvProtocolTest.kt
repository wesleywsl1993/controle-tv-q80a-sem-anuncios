package br.com.wesley.controleq80a

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.Base64
import okhttp3.HttpUrl.Companion.toHttpUrl

class TvProtocolTest {
    @Test fun acceptsOnlyPrivateLiteralIpv4() {
        listOf("10.0.0.8", "172.16.1.2", "172.31.255.254", "192.168.1.50").forEach {
            assertTrue(it, TvProtocol.validIp(it))
        }
        listOf("", "192.168.1.300", "192.168.1.1/evil", "8.8.8.8", "127.0.0.1",
            "172.32.0.1", "tv.local", "http://192.168.1.2").forEach {
            assertFalse(it, TvProtocol.validIp(it))
        }
    }

    @Test fun keyCommandHasExpectedFields() {
        val json = JSONObject(TvProtocol.key("KEY_HOME"))
        assertEquals("ms.remote.control", json.getString("method"))
        val params = json.getJSONObject("params")
        assertEquals("Click", params.getString("Cmd"))
        assertEquals("KEY_HOME", params.getString("DataOfCmd"))
        assertEquals("SendRemoteKey", params.getString("TypeOfRemote"))
    }

    @Test fun textCommandEncodesUtf8() {
        val params = JSONObject(TvProtocol.text("ação")).getJSONObject("params")
        assertEquals("SendInputString", params.getString("TypeOfRemote"))
        assertEquals("base64", params.getString("DataOfCmd"))
        assertEquals("ação", String(Base64.getDecoder().decode(params.getString("Cmd")), Charsets.UTF_8))
    }

    @Test fun appIdCannotInjectPathOrQuery() {
        assertTrue(TvProtocol.validAppId("3201606009684"))
        assertFalse(TvProtocol.validAppId("../api"))
        assertFalse(TvProtocol.validAppId("app?next=https://example.com"))
    }

    @Test fun websocketHandshakeUrlUsesHttpsAndEncodesToken() {
        assertThrows(IllegalArgumentException::class.java) {
            "wss://192.168.12.30:8002/api/v2/channels/samsung.remote.control".toHttpUrl()
        }
        val url = TvProtocol.remoteUrl("192.168.12.30", true, "a&b")
        assertEquals("https", url.scheme)
        assertEquals("192.168.12.30", url.host)
        assertEquals(8002, url.port)
        assertEquals("a&b", url.queryParameter("token"))
        assertEquals("Controle Q80A", String(Base64.getDecoder().decode(url.queryParameter("name")), Charsets.UTF_8))
        val fallback = TvProtocol.remoteUrl("192.168.12.30", false, "")
        assertEquals("http", fallback.scheme)
        assertEquals(8001, fallback.port)
        assertNull(fallback.queryParameter("token"))
    }
}
