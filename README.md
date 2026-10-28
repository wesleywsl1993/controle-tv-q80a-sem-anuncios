# Controle TV Q80A sem anúncios

Um controle para TV Samsung pela rede local. O projeto nasceu para uma QN55Q80AAGXZD, mas pode servir como ponto de partida para outras TVs Samsung com Tizen. Ele oferece setas, OK, voltar, início, volume, canais, mídia, teclado e atalhos para Spotify, YouTube e Netflix.

O app não tem anúncios, analytics ou conta. Os comandos passam pela rede da casa; não há backend em nuvem. O celular e a TV precisam estar no mesmo Wi-Fi.

## Escolha como usar

- **Android:** o app está em [ControleQ80A](ControleQ80A/). A versão atual é a **0.1.3**. Informe o IP da TV e autorize o controle na televisão.
- **iPhone pelo Windows:** a pasta [iphone-tv-control](iphone-tv-control/) contém uma página que abre no Safari. O Windows faz a ponte com a TV e precisa ficar ligado durante o uso. Início, volume, Spotify e o comando para ligar a TV pela rede foram testados em um iPhone.
- **App nativo para iPhone:** há um projeto SwiftUI em [ControleQ80AiOS](ControleQ80AiOS/). Ele ainda não foi compilado nem testado em um iPhone. Para instalar essa versão, é preciso um Mac com Xcode e assinatura Apple. Os [requisitos do Xcode](https://developer.apple.com/xcode/system-requirements/) são mantidos pela Apple.

## Android

Abra a pasta `ControleQ80A` no Android Studio. O projeto usa o Android SDK 35 e JDK 17 ou 21. Para compilar o APK e executar os testes no Windows, abra um terminal nessa pasta e rode:

```powershell
.\gradlew.bat :app:assembleDebug :app:testDebugUnitTest
```

Depois de um build bem-sucedido, o APK estará em `ControleQ80A/app/build/outputs/apk/debug/app-debug.apk`. Instale-o no celular, abra as configurações do controle e informe o IP da TV. Na primeira conexão, aceite o pedido que aparecer na televisão.

O IP e o token de pareamento ficam guardados no aparelho. O app tenta reconectar quando a conexão cai e quando você volta à tela; o botão de seta circular permite tentar novamente na hora. Se tocar em um comando enquanto ele ainda estiver reconectando, espere a mensagem **Conectado à TV** e toque de novo. A reconexão após um período longo sem uso ainda precisa ser testada na TV.

O controle de volume é relativo: arraste para um lado ou para o outro para enviar comandos de aumentar ou diminuir. A posição central não representa o volume atual da TV.

Para tentar ligar a TV quando ela estiver em espera, preencha o MAC da TV e o broadcast da rede em Configurações e toque em **Ligar TV pela rede**. O app envia um pacote Wake-on-LAN pela interface de rede conectada. A opção **Ligar com celular**, quando disponível, precisa estar ativada na TV. O envio não confirma que ela ligou: o resultado depende da TV, do tipo de espera e da rede.

## iPhone usando um Windows

Essa opção usa o Safari como controle e uma pequena ponte no Windows para se comunicar com a TV. Deixe o iPhone, o Windows e a televisão na mesma rede e mantenha o computador ligado.

### Prepare o Windows

Você vai precisar de Python 3, PowerShell 7 e do pacote Python `cryptography`. Depois de instalar Python e PowerShell, abra um terminal na pasta do projeto e instale o pacote:

```powershell
python -m pip install cryptography
```

Com a TV ligada, inicie o pareamento:

```powershell
pwsh -NoProfile -File .\tv-lan-probe\probe.ps1
```

O programa pede o IP da TV. Aceite o pedido de controle na tela da televisão. O Windows guarda o token protegido para a conta atual e registra a impressão digital do certificado da TV.

Se você já usa o app Android **debug** pareado e não consegue aceitar outro pedido na TV, existe uma alternativa: conecte esse Android por ADB, com a depuração autorizada, e execute o importador abaixo. Ele pede o IP que está salvo no app Android e transfere o token para o Windows sem exibi-lo no terminal. Em seguida, execute `probe.ps1` novamente para conectar e registrar o certificado da TV. Desative a depuração no Android quando terminar.

```powershell
pwsh -NoProfile -File .\tv-lan-probe\import-android-token.ps1
```

### Abra o controle no iPhone

Execute `iphone-tv-control/iniciar-controle-iphone.cmd` no Windows para iniciar o servidor HTTPS. O programa pede as informações da rede, mostra um endereço para abrir no Safari e gera um PIN temporário. Digite esse PIN na página. Depois de conectado, use **Compartilhar → Adicionar à Tela de Início** se quiser abrir o controle por um ícone.

Para iniciar o controle automaticamente ao entrar na conta do Windows e reiniciar o servidor se ele parar, execute:

```powershell
pwsh -NoProfile -File .\iphone-tv-control\instalar-inicializacao.ps1
```

O instalador pede os endereços da rede e cria um atalho na pasta de inicialização da conta atual. Para consultar o PIN temporário gerado pelo serviço, abra `iphone-tv-control/mostrar-pin.cmd` no Windows; se o PIN anterior tiver expirado ou já tiver sido usado, o programa pede outro ao serviço. A sessão HTTPS fica salva e é renovada ao usar o controle. O computador precisa estar ligado, com a sessão Windows iniciada e sem suspensão. Reserve o IP do Windows no roteador para que o endereço salvo no iPhone continue apontando para ele.

Na página, **Ligar TV pela rede** envia Wake-on-LAN. Na primeira vez, abra a configuração desse botão e informe o MAC da TV e o broadcast da rede. Na QN55Q80AAGXZD usada no projeto, a TV ligou após aproximadamente 30 segundos em espera, com **Ligar com celular** ativado; os outros botões do controle voltaram a funcionar em seguida. A confirmação de envio indica apenas que o pacote saiu do Windows; o resultado pode variar conforme o tempo em espera e a rede.

Também testamos o reinício do servidor: ele voltou sozinho e o iPhone abriu o controle sem pedir o PIN novamente. A estabilidade após várias horas de inatividade ainda precisa de acompanhamento, assim como o Wake-on-LAN depois de um período longo com a TV desligada.

O HTTPS usa um certificado local autoassinado. Confira a impressão digital exibida no terminal antes de confiar nele. No Safari usado durante os testes, essa conexão apresentou instabilidade. A alternativa testada foi `iphone-tv-control/iniciar-teste-iphone.cmd`, que inicia uma sessão HTTP temporária.

**No modo HTTP, a comunicação entre o iPhone e o Windows não é criptografada.** Use-o apenas em uma rede privada e confiável, sem encaminhar a porta no roteador, e feche o servidor quando terminar. Nesse modo, a sessão expira em uma hora e é perdida ao reiniciar o servidor. O token da TV permanece no Windows.

### O que preencher

Os dados da sua rede não vêm preenchidos. O iniciador pede os valores abaixo:

| Campo | Onde encontrar ou como usar |
| --- | --- |
| IP da TV | Nas configurações de rede da televisão. Use o endereço atual da TV no app ou quando o programa pedir. |
| IPv4 do Windows | Nas informações da conexão Wi-Fi do Windows. É o endereço do computador que vai servir a página para o iPhone. |
| Sub-rede permitida | A faixa da rede local em formato CIDR. Ela deve incluir o Windows e o iPhone; o servidor recusa conexões de fora dela. |
| Porta | O iniciador usa a porta 8765. Quem iniciar `server.py` diretamente pode alterá-la com `--port`. |
| PIN | É temporário e deve ser digitado no Safari. Aparece no terminal ou pode ser consultado com `mostrar-pin.cmd` quando o serviço está em segundo plano. |
| IDs dos aplicativos | Podem ser alterados nas configurações do controle. A consulta à lista instalada depende da resposta da TV. |

O token Samsung é fornecido pela TV durante o pareamento, não precisa ser digitado no navegador e não deve ser compartilhado. Arquivos de pareamento, sessão, certificados e chaves ficam em pastas `.local`, ignoradas pelo Git.

## App nativo para iPhone

Em um Mac, abra `ControleQ80AiOS/ControleQ80AiOS.xcodeproj` no Xcode. Selecione sua equipe em **Signing & Capabilities**, ajuste o identificador do app se necessário e escolha o iPhone como destino. No aplicativo, informe o IP da TV e aceite os pedidos de acesso à rede e de autorização na televisão.

Essa versão ainda precisa ser compilada e validada em um Mac, um iPhone e uma TV. O projeto usa IP informado manualmente; descoberta multicast no iOS depende de uma [permissão específica da Apple](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast).

## Limitações conhecidas

- A lista de aplicativos pode não ser retornada pela TV. Nesse caso, preencha os IDs manualmente.
- O envio de texto depende do firmware e do campo selecionado na TV. As setas e o OK continuam disponíveis para usar o teclado da televisão.
- O botão de energia não garante ligar a TV em standby profundo. O Wake-on-LAN depende da TV e da rede e precisa ser confirmado no aparelho.
- A Alexa da TV não está integrada ao controle local. A Q80A informa suporte à Alexa integrada e a comando de voz à distância: configure-a em **Configurações → Geral → Voz → Assistente de voz**, entre na conta Amazon e confira se o microfone da TV está ativado. Na TV usada no projeto, a Alexa respondeu e alterou o volume por voz sem controle físico. Outra opção é vincular a TV ao SmartThings e habilitar a skill SmartThings no app Alexa. Essas opções usam serviços externos e contas; os recursos básicos do SmartThings não exigem mensalidade. A disponibilidade de comandos varia por modelo e região. Consulte as orientações da [Samsung sobre Alexa](https://news.samsung.com/br/aprenda-o-passo-a-passo-para-usar-alexa-na-smart-tv-samsung) e sobre [comando de voz na TV](https://www.samsung.com/br/support/tv-audio-video/o-comando-de-voz-da-minha-smart-tv-samsung-nao-funciona/).
- No Android, a conexão tenta WSS na porta 8002. Em uma falha apropriada de conexão, pode recorrer a WS na porta 8001, que transmite o token sem TLS na rede local. A ponte Windows e o projeto iOS usam WSS.

O comportamento pode variar conforme o modelo, a região e o firmware. Na TV usada no desenvolvimento, os controles básicos do Android e o atalho Spotify foram confirmados; teste os demais recursos na sua televisão.
