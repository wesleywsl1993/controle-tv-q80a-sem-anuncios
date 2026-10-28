# Controle TV Q80A sem anúncios

Controle local para uma Samsung QN55Q80AAGXZD (Tizen), feito como projeto pessoal. Não há anúncios, analytics, conta, backend em nuvem ou serviço pago. O telefone, a TV e, na alternativa web, o Windows precisam estar na mesma rede local.

## O que há neste repositório

| Pasta | Função | Estado de validação |
| --- | --- | --- |
| `ControleQ80A/` | App Android em Kotlin e Jetpack Compose | APK debug `0.1.2` compilado; cinco testes unitários passaram. O usuário confirmou controles básicos e atalho Spotify na TV. A reconexão após longo tempo ocioso ainda precisa de teste físico. |
| `ControleQ80AiOS/` | Código fonte SwiftUI para um app nativo | Criado no Windows. Ainda não foi compilado no Xcode nem instalado em um iPhone. |
| `iphone-tv-control/` | Controle web aberto no Safari, servido por um Windows da rede | Testado pelo usuário no iPhone com a modalidade HTTP local: PIN, Início, volume e Spotify funcionaram. O modo HTTPS autoassinado não se mostrou estável no Safari testado. |
| `tv-lan-probe/` | Pareamento e ponte Windows→TV por WSS | O comando Início e a abertura do Spotify foram confirmados na TV do usuário. |
| `iphone-lan-probe/` | Diagnóstico inicial da comunicação iPhone→Windows | Não envia comandos à TV. |

## Limitação do Mac e alternativa para iPhone

Um app iOS nativo precisa ser compilado e assinado em um **Mac com Xcode** e uma equipe de assinatura Apple ([requisitos do Xcode](https://developer.apple.com/xcode/system-requirements/)). Este projeto foi desenvolvido em Windows, sem acesso a Mac. Por isso, o código SwiftUI está disponível para quem tiver esse ambiente, mas **não há IPA nativo pronto** e não se afirma que essa versão tenha sido testada no iPhone.

A alternativa que funcionou foi uma página local aberta no Safari do iPhone. Um servidor Python no Windows recebe os comandos da página; uma ponte PowerShell no mesmo Windows conversa com a TV pela rede local. O Windows deve permanecer ligado e acessível. O atalho **Adicionar à Tela de Início** abre a página como controle, mas não a torna offline. O token Samsung fica no Windows e nunca é entregue ao navegador.

## Campos que cada usuário deve preencher

Nenhum endereço da rede doméstica do autor, PIN, token, impressão digital de certificado ou credencial pessoal vem preenchido no código publicado. Os endereços que aparecem nos testes são apenas dados de teste.

| Campo | Onde informar | O que significa |
| --- | --- | --- |
| IP da TV | Configurações do Android ou do app SwiftUI; `tv-lan-probe` e servidor web no Windows | Endereço IPv4 privado atual da TV na rede local. Se ele mudar, atualize o valor e refaça o pareamento quando necessário. |
| IPv4 deste Windows | Ao iniciar `iphone-tv-control/start.ps1` | Endereço IPv4 da interface do Windows conectada à mesma rede da TV e do iPhone. O servidor escuta somente nesse endereço. |
| Sub-rede permitida | Ao iniciar `iphone-tv-control/start.ps1` | Faixa da rede local em notação CIDR que contém o Windows e o iPhone. O servidor recusa clientes fora dessa faixa. |
| Porta do servidor web | Parâmetro `--port` de `server.py` | Porta local pela qual o iPhone acessa o Windows. O iniciador usa 8765; não abra essa porta no roteador. |
| IDs dos aplicativos | Configurações do controle | Identificadores de Spotify, YouTube e Netflix instalados na própria TV. São editáveis; a descoberta de apps pode não ser respondida pelo firmware. |
| Token Samsung | Gerado pela TV após autorização | Credencial de pareamento. O Android a guarda nas preferências privadas; o app iOS usa Keychain; a ponte Windows usa DPAPI em `tv-lan-probe/.local/`. Não copie para o repositório. |
| PIN do iPhone | Exibido no terminal ao iniciar o servidor web | Código temporário para autorizar o navegador. É gerado em cada início e digitado na página. Nenhum PIN fixo é distribuído. |
| Certificado e impressão digital | Criados e guardados localmente no Windows | Identificam o servidor HTTPS e o certificado autoassinado da TV. Confira a impressão digital antes de confiar no servidor; não publique chaves privadas. |
| Equipe de assinatura Apple | Xcode, em Signing & Capabilities | Conta/equipe usada para assinar e instalar o app SwiftUI em um iPhone. Só é necessária para a versão nativa. |
| Identificador do app iOS | Xcode, nas configurações do alvo | Nome exclusivo do pacote na sua equipe Apple. Ajuste se o identificador incluído no projeto já estiver ocupado. |

## Android

Abra `ControleQ80A/` no Android Studio com Android SDK 35 e JDK 17 ou 21. Execute `gradlew.bat :app:assembleDebug :app:testDebugUnitTest` no Windows, ou `./gradlew :app:assembleDebug :app:testDebugUnitTest` em outro sistema. O APK fica em `ControleQ80A/app/build/outputs/apk/debug/` apenas após um build bem-sucedido. A chave de assinatura debug é local e não é publicada.

No app, informe o IP da TV e aceite o pedido de autorização na televisão. IP e token persistem localmente. O controle tenta reconectar após uma queda e ao voltar do segundo plano; o ícone circular força uma tentativa imediata. Um comando tocado durante a desconexão deve ser repetido após aparecer **Conectado à TV**. O slider de volume é relativo e não mostra o nível real da TV.

## App nativo para iPhone

Quem tiver Mac deve abrir `ControleQ80AiOS/ControleQ80AiOS.xcodeproj` no Xcode, selecionar a própria equipe de assinatura e informar o IP da TV em Configurações. O iPhone precisa autorizar acesso à rede local e a TV precisa autorizar o pareamento. Não há descoberta multicast no código iOS; essa capacidade depende de [entitlement restrito pela Apple](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast). A compilação, o pareamento e os comandos dessa versão ainda exigem validação em Mac, iPhone e TV reais.

## Controle web no iPhone via Windows

Instale Python 3 com o pacote `cryptography` e PowerShell 7 no Windows. Primeiro, use `tv-lan-probe/probe.ps1` para autorizar a ponte com a TV. Se a TV já estiver autorizada pelo app Android debug e não houver como aceitar um novo pedido na tela, `tv-lan-probe/import-android-token.ps1` permite transferir o token por ADB de um único Android autorizado para a DPAPI da conta Windows, sem salvar texto puro. Depois, use `probe.ps1` para fixar o certificado da TV. Desative a depuração Android após a transferência.

Execute `iphone-tv-control/iniciar-controle-iphone.cmd` para HTTPS ou `iphone-tv-control/iniciar-teste-iphone.cmd` para a prova HTTP local. O iniciador pergunta o IPv4 do Windows, a sub-rede permitida e o IPv4 da TV, sem valores de exemplo. Abra no Safari o endereço mostrado no terminal e digite o PIN temporário exibido ali. Após confirmar o controle, use **Compartilhar → Adicionar à Tela de Início**.

O teste HTTP foi o caminho validado no iPhone do usuário, mas o tráfego iPhone→Windows **não é criptografado**. Uma pessoa capaz de observar essa rede pode capturar a sessão e comandar a TV. Use apenas em rede doméstica privada e confiável, não encaminhe a porta no roteador e encerre o servidor quando terminar. O HTTPS local usa certificado autoassinado; a confiança inicial precisa ser conferida no iPhone e não foi estável no Safari testado. O token da TV permanece fora do navegador em ambas as modalidades. Os arquivos em `.local/` contêm material de pareamento e são ignorados pelo Git.

## Limites do protocolo

- A TV pode não responder à consulta de apps; os IDs continuam editáveis.
- O envio de texto depende do campo selecionado e do firmware da TV.
- `KEY_POWER` não garante ligar a TV em standby profundo. Wake-on-LAN não foi implementado sem confirmação de suporte e configuração de endereço MAC e broadcast pelo usuário.
- A Alexa da TV não foi integrada. Não há protocolo local documentado neste canal de controle para enviar comandos à Alexa; o uso da assistente pela TV segue a configuração própria da Samsung/Amazon e pode exigir conta e serviços externos.
- O Android usa WSS na porta 8002 e só tenta WS na porta 8001 em falha apropriada de conexão da porta segura. Esse fallback transmite token sem TLS na rede local. A ponte Windows e o código iOS usam apenas WSS.

Este repositório contém apenas código fonte e documentação pública. Arquivos de sessão, tokens, certificados, chaves de assinatura, dados do telefone do autor, relatórios e configurações da rede doméstica não fazem parte dele.
