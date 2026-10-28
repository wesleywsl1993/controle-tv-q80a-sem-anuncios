package br.com.wesley.controleq80a

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.automirrored.filled.VolumeDown
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import kotlin.math.roundToInt

private val Bg = Color(0xFF080B12)
private val Panel = Color(0xFF151B28)
private val Accent = Color(0xFF78A9FF)
private val Muted = Color(0xFF9BA8BC)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val prefs = getSharedPreferences("tv_remote", Context.MODE_PRIVATE)
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(primary = Accent, background = Bg, surface = Panel)) {
                RemoteScreen(prefs, lifecycle)
            }
        }
    }
}

@Composable
private fun RemoteScreen(prefs: android.content.SharedPreferences, lifecycle: Lifecycle) {
    var tvIp by remember { mutableStateOf(prefs.getString("ip", "") ?: "") }
    var token by remember { mutableStateOf(prefs.getString("token", "") ?: "") }
    var status by remember { mutableStateOf("Configure o IP da TV para começar.") }
    var connectionState by remember { mutableStateOf(TvState.DISCONNECTED) }
    var installedApps by remember { mutableStateOf<List<TvApp>>(emptyList()) }
    var spotifyId by remember { mutableStateOf(prefs.getString("spotify_id", "") ?: "") }
    var youtubeId by remember { mutableStateOf(prefs.getString("youtube_id", "") ?: "") }
    var netflixId by remember { mutableStateOf(prefs.getString("netflix_id", "") ?: "") }
    var showSettings by remember { mutableStateOf(tvIp.isBlank()) }
    var showKeyboard by remember { mutableStateOf(false) }
    var searchText by remember { mutableStateOf("") }

    val client = remember {
        TvRemoteClient(
            onState = { state, message -> connectionState = state; status = message },
            onToken = { received ->
                if (prefs.edit().putString("token", received).commit()) token = received
                else status = "Falha ao salvar o pareamento local."
            },
            onApps = { apps -> installedApps = apps; status = if (apps.isEmpty()) "TV não informou apps instalados; edite os IDs manualmente." else "${apps.size} apps recebidos da TV. Confira os IDs nas configurações." }
        )
    }
    val currentIp by rememberUpdatedState(tvIp)
    val currentToken by rememberUpdatedState(token)
    DisposableEffect(lifecycle, client) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> if (currentIp.isNotBlank()) client.connect(currentIp, currentToken)
                Lifecycle.Event.ON_STOP -> client.disconnect()
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            client.disconnect()
        }
    }

    Surface(modifier = Modifier.fillMaxSize(), color = Bg) {
        Column(
            modifier = Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("CONTROLE Q80A", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                    Text("Samsung QLED · rede local · sem anúncios", color = Muted, fontSize = 12.sp)
                }
                IconButton(onClick = { client.connect(tvIp, token) }, enabled = TvProtocol.validIp(tvIp)) {
                    Icon(Icons.Default.Refresh, "Reconectar à TV", tint = if (TvProtocol.validIp(tvIp)) Accent else Muted)
                }
                IconButton(onClick = { showSettings = true }) { Icon(Icons.Default.Settings, "Configurações", tint = Muted) }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(9.dp), modifier = Modifier.fillMaxWidth()) {
                AppShortcut("Spotify", spotifyId, "S", Modifier.weight(1f), client)
                AppShortcut("YouTube", youtubeId, "▶", Modifier.weight(1f), client)
                AppShortcut("Netflix", netflixId, "N", Modifier.weight(1f), client)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(9.dp), modifier = Modifier.fillMaxWidth()) {
                ActionTile("Ligar / desligar", Icons.Default.PowerSettingsNew, Modifier.weight(1f)) { client.sendKey("KEY_POWER") }
                ActionTile("Início", Icons.Default.Home, Modifier.weight(1f)) { client.sendKey("KEY_HOME") }
                ActionTile("Teclado", Icons.Default.Keyboard, Modifier.weight(1f)) { showKeyboard = true }
            }

            // Direction pad
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                RoundKey("↑", "Cima") { client.sendKey("KEY_UP") }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    RoundKey("←", "Esquerda") { client.sendKey("KEY_LEFT") }
                    Button(onClick = { client.sendKey("KEY_ENTER") }, shape = CircleShape, modifier = Modifier.size(82.dp), colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Bg), contentPadding = PaddingValues(0.dp)) {
                        Text("OK", fontWeight = FontWeight.Black, fontSize = 19.sp)
                    }
                    RoundKey("→", "Direita") { client.sendKey("KEY_RIGHT") }
                }
                RoundKey("↓", "Baixo") { client.sendKey("KEY_DOWN") }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(9.dp), modifier = Modifier.fillMaxWidth()) {
                ActionTile("Voltar", Icons.AutoMirrored.Filled.ArrowBack, Modifier.weight(1f)) { client.sendKey("KEY_RETURN") }
                ActionTile("Mudo", Icons.AutoMirrored.Filled.VolumeOff, Modifier.weight(1f)) { client.sendKey("KEY_MUTE") }
                ActionTile("Menu", Icons.Default.Settings, Modifier.weight(1f)) { client.sendKey("KEY_MENU") }
            }
            var volumeGesture by remember { mutableFloatStateOf(10f) }
            var lastVolumeStep by remember { mutableIntStateOf(10) }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                IconButton(onClick = { client.sendKey("KEY_VOLDOWN") }) { Icon(Icons.AutoMirrored.Filled.VolumeDown, "Diminuir volume", tint = Color.White) }
                Slider(
                    value = volumeGesture,
                    onValueChange = { value ->
                        val step = value.roundToInt().coerceIn(0, 20)
                        volumeGesture = step.toFloat()
                        val delta = step - lastVolumeStep
                        if (delta != 0) {
                            lastVolumeStep = step
                            client.adjustVolume(delta)
                        }
                    },
                    valueRange = 0f..20f,
                    steps = 19,
                    onValueChangeFinished = {
                        volumeGesture = 10f
                        lastVolumeStep = 10
                    },
                    modifier = Modifier.weight(1f).semantics {
                        contentDescription = "Volume relativo: arraste à esquerda para diminuir ou à direita para aumentar"
                    }
                )
                IconButton(onClick = { client.sendKey("KEY_VOLUP") }) { Icon(Icons.AutoMirrored.Filled.VolumeUp, "Aumentar volume", tint = Color.White) }
            }
            Text("Arraste para ajustar o volume; o centro não representa o volume atual da TV.", color = Muted, fontSize = 11.sp)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                TextButton(onClick = { client.sendKey("KEY_CHDOWN") }) { Text("Canal −") }
                TextButton(onClick = { client.sendKey("KEY_CHUP") }) { Text("Canal +") }
                TextButton(onClick = { client.sendKey("KEY_PLAY") }) { Text("▶") }
                TextButton(onClick = { client.sendKey("KEY_PAUSE") }) { Text("Ⅱ") }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                TextButton(onClick = { client.sendKey("KEY_REWIND") }) { Text("⏪") }
                TextButton(onClick = { client.sendKey("KEY_FF") }) { Text("⏩") }
                TextButton(onClick = { client.sendKey("KEY_STOP") }) { Text("■") }
            }
            Text(status, color = if (connectionState == TvState.CONNECTED) Accent else Muted, fontSize = 12.sp, lineHeight = 16.sp, modifier = Modifier.fillMaxWidth())
        }
    }

    if (showSettings) {
        var draftIp by remember(tvIp) { mutableStateOf(tvIp) }
        var draftSpotify by remember(spotifyId) { mutableStateOf(spotifyId) }
        var draftYoutube by remember(youtubeId) { mutableStateOf(youtubeId) }
        var draftNetflix by remember(netflixId) { mutableStateOf(netflixId) }
        fun saveDraft(): Boolean {
            val nextIp = draftIp.trim()
            if (!TvProtocol.validIp(nextIp)) {
                status = "Informe um IPv4 privado válido."
                return false
            }
            if (listOf(draftSpotify, draftYoutube, draftNetflix).any {
                    it.isNotBlank() && !TvProtocol.validAppId(it.trim())
                }) {
                status = "Confira os IDs dos aplicativos."
                return false
            }
            val nextSpotify = draftSpotify.trim()
            val nextYoutube = draftYoutube.trim()
            val nextNetflix = draftNetflix.trim()
            val ipChanged = nextIp != tvIp
            val edit = prefs.edit()
                .putString("ip", nextIp)
                .putString("spotify_id", nextSpotify)
                .putString("youtube_id", nextYoutube)
                .putString("netflix_id", nextNetflix)
            if (ipChanged) edit.remove("token")
            if (!edit.commit()) {
                status = "Não foi possível salvar as configurações locais."
                return false
            }
            tvIp = nextIp
            spotifyId = nextSpotify
            youtubeId = nextYoutube
            netflixId = nextNetflix
            if (ipChanged) {
                token = ""
                installedApps = emptyList()
            }
            return true
        }
        AlertDialog(
            onDismissRequest = { showSettings = false },
            title = { Text("Conectar à TV") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.verticalScroll(rememberScrollState())) {
                    Text("Celular e TV precisam estar no mesmo Wi-Fi. Na TV, consulte o IP em Configurações → Geral → Rede → Status da rede.", fontSize = 13.sp)
                    OutlinedTextField(value = draftIp, onValueChange = { draftIp = it }, label = { Text("IP da TV") }, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri))
                    TextButton(onClick = { client.discover { draftIp = it; status = "Samsung encontrada em $it. Confirme o IP e conecte." } }) { Text("Procurar TV no Wi-Fi") }
                    TextButton(onClick = {
                        val candidate = draftIp.trim()
                        if (TvProtocol.validIp(candidate)) client.connect(candidate, if (candidate == tvIp) token else "")
                        else status = "Informe um IPv4 privado válido."
                    }) { Text("Testar conexão sem salvar") }
                    TextButton(onClick = { client.requestApps() }) { Text("Consultar apps instalados") }
                    Text(status, color = if (connectionState == TvState.CONNECTED) Accent else Muted, fontSize = 12.sp)
                    Text("Após conectar e autorizar na TV, consulte os apps. Se a TV não responder, use um ID de referência e confirme se o app abre.", fontSize = 12.sp, color = Muted)
                    if (installedApps.isNotEmpty()) {
                        Text("Apps informados pela TV (${installedApps.size}). Toque para usar o ID:", fontSize = 11.sp)
                        installedApps.filter { app -> listOf("spotify", "youtube", "netflix").any { app.name.contains(it, true) } }
                            .forEach { app ->
                                TextButton(onClick = {
                                    when {
                                        app.name.contains("spotify", true) -> draftSpotify = app.id
                                        app.name.contains("youtube", true) -> draftYoutube = app.id
                                        app.name.contains("netflix", true) -> draftNetflix = app.id
                                    }
                                }) { Text("${app.name}: ${app.id}") }
                            }
                    }
                    OutlinedTextField(draftSpotify, { draftSpotify = it }, label = { Text("ID Spotify") }, singleLine = true)
                    OutlinedTextField(draftYoutube, { draftYoutube = it }, label = { Text("ID YouTube") }, singleLine = true)
                    OutlinedTextField(draftNetflix, { draftNetflix = it }, label = { Text("ID Netflix") }, singleLine = true)
                    TextButton(onClick = {
                        draftSpotify = "201606009684"
                        draftYoutube = "111299001912"
                        draftNetflix = "3201907018807"
                        status = "IDs informados para esta TV preenchidos. Salve para usá-los."
                    }) { Text("Preencher IDs informados para esta TV") }
                    TextButton(onClick = { token = ""; prefs.edit().remove("token").apply(); client.disconnect(); status = "Token local apagado. A próxima conexão exigirá autorização." }) { Text("Limpar token") }
                    Text("IP salvo: ${if (tvIp.isBlank()) "nenhum" else tvIp} · Pareamento salvo: ${if (token.isBlank()) "não" else "sim"}", fontSize = 12.sp, color = Muted)
                    Text("Na primeira conexão, aceite a solicitação de controle que aparecer na televisão.", color = Muted, fontSize = 12.sp)
                }
            },
            confirmButton = { TextButton(onClick = {
                if (saveDraft()) client.connect(tvIp, token)
            }) { Text("Salvar e conectar") } },
            dismissButton = { TextButton(onClick = { showSettings = false }) { Text("Voltar ao controle") } },
            containerColor = Panel
        )
    }

    if (showKeyboard) {
        AlertDialog(
            onDismissRequest = { showKeyboard = false },
            title = { Text("Enviar texto à TV") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Abra um campo de busca na TV. O suporte a texto depende do firmware. Se falhar, use setas e OK no teclado da TV.", fontSize = 12.sp, color = Muted)
                    OutlinedTextField(value = searchText, onValueChange = { searchText = it }, label = { Text("Pesquisar…") }, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text))
                }
            },
            confirmButton = { TextButton(onClick = { client.sendText(searchText); showKeyboard = false }) { Text("Enviar") } },
            dismissButton = { TextButton(onClick = { showKeyboard = false }) { Text("Cancelar") } },
            containerColor = Panel
        )
    }
}

@Composable
private fun AppShortcut(label: String, appId: String, symbol: String, modifier: Modifier, client: TvRemoteClient) {
    Button(onClick = { client.launchApp(appId) }, enabled = appId.isNotBlank(), modifier = modifier.height(70.dp), shape = RoundedCornerShape(16.dp), colors = ButtonDefaults.buttonColors(containerColor = Panel, contentColor = Color.White), contentPadding = PaddingValues(5.dp)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(symbol, color = Accent, fontWeight = FontWeight.Black, fontSize = 20.sp)
            Text(label, fontSize = 12.sp)
        }
    }
}

@Composable
private fun ActionTile(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, modifier: Modifier = Modifier, onClick: () -> Unit) {
    FilledTonalButton(onClick = onClick, modifier = modifier.height(62.dp), shape = RoundedCornerShape(15.dp), colors = ButtonDefaults.filledTonalButtonColors(containerColor = Panel, contentColor = Color.White), contentPadding = PaddingValues(5.dp)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp))
            Text(label, fontSize = 10.sp, maxLines = 1)
        }
    }
}

@Composable
private fun RoundKey(label: String, description: String, onClick: () -> Unit) {
    FilledTonalButton(onClick = onClick, modifier = Modifier.size(68.dp).semantics { contentDescription = description }, shape = CircleShape, colors = ButtonDefaults.filledTonalButtonColors(containerColor = Panel, contentColor = Color.White), contentPadding = PaddingValues(0.dp)) {
        Text(label, fontSize = 28.sp, fontWeight = FontWeight.Light)
    }
}
