const $ = id => document.getElementById(id);
let csrf = '';
let commandQueue = Promise.resolve();
let lastVolume = 10;
let pendingVolume = 0;
let sendingVolume = false;

function status(text, online) {
  $('status').textContent = text;
  $('status').className = 'status ' + (online ? 'online' : 'offline');
}
function feedback(text) { $('feedback').textContent = text; }

async function timedFetch(path, options, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try { return await fetch(path, {...options, signal:controller.signal}); }
  finally { clearTimeout(timer); }
}

async function post(path, value, authenticated = true) {
  const headers = {'Content-Type':'application/json'};
  if (authenticated) headers['X-CSRF-Token'] = csrf;
  const response = await timedFetch(path, {method:'POST', headers, body:JSON.stringify(value), credentials:'same-origin', cache:'no-store'}, 35000);
  const result = await response.json();
  if (authenticated && response.status === 403 && result.error === 'Sessão inválida') refresh();
  if (!response.ok || result.ok === false) throw new Error(result.error || result.message || 'Falha no comando');
  return result;
}

async function refresh() {
  try {
    const response = await timedFetch('/api/status', {credentials:'same-origin', cache:'no-store'}, 8000);
    if (response.status === 401) {
      $('connection-help').hidden = true; $('login').hidden = false; $('remote').hidden = true; status('Parear iPhone', false); return;
    }
    if (!response.ok) throw new Error('Falha ao consultar o Windows');
    const result = await response.json();
    csrf = result.csrf;
    $('connection-help').hidden = true; $('login').hidden = true; $('remote').hidden = false;
    status(result.connected ? 'TV conectada' : 'TV indisponível', result.connected);
    if (!$('apps-form').contains(document.activeElement)) {
      for (const [name,id] of Object.entries(result.apps)) $(name).value = id;
    }
    if (result.wake && !$('wake-form').contains(document.activeElement)) {
      $('wake-mac').value = result.wake.mac;
      $('wake-broadcast').value = result.wake.broadcast;
    }
  } catch (_) {
    status('Windows offline', false);
    $('connection-help').hidden = false;
    $('connection-message').textContent = 'Sem resposta do Windows. Confira se o servidor está aberto e se o endereço do computador mudou.';
    feedback('Sem resposta do Windows. Confira a rede local.');
  }
}
$('retry-connection').addEventListener('click', refresh);
$('wake-tv').addEventListener('click', async () => {
  try { const result = await post('/api/wake', {}); feedback(result.message); }
  catch (error) { feedback(error.message); }
});
$('wake-form').addEventListener('submit', async event => {
  event.preventDefault();
  try {
    await post('/api/wake-settings', {mac:$('wake-mac').value.trim(), broadcast:$('wake-broadcast').value.trim()});
    feedback('Configuração para ligar a TV salva no Windows.');
  } catch (error) { feedback(error.message); }
});

function command(value, message = 'Comando enviado') {
  commandQueue = commandQueue.catch(() => {}).then(async () => {
    try { await post('/api/command', value); feedback(message); status('TV conectada', true); }
    catch (error) { feedback(error.message); status('TV indisponível', false); }
  });
  return commandQueue;
}

document.querySelectorAll('[data-key]').forEach(button => button.addEventListener('click', () =>
  command({type:'key', key:button.dataset.key, count:1})));
document.querySelectorAll('[data-app]').forEach(button => button.addEventListener('click', () =>
  command({type:'app', app:button.dataset.app}, 'Abertura solicitada. Confira a TV.')));

$('volume').addEventListener('input', event => {
  const current = Number(event.target.value);
  const delta = current - lastVolume;
  lastVolume = current;
  if (delta) { pendingVolume += delta; flushVolume(); }
});
$('volume').addEventListener('change', () => { $('volume').value = 10; lastVolume = 10; });

async function flushVolume() {
  if (sendingVolume) return;
  sendingVolume = true;
  while (pendingVolume) {
    const amount = Math.sign(pendingVolume) * Math.min(Math.abs(pendingVolume), 8);
    pendingVolume -= amount;
    await command({type:'key',key:amount > 0 ? 'KEY_VOLUP' : 'KEY_VOLDOWN',count:Math.abs(amount)});
  }
  sendingVolume = false;
}

$('text-form').addEventListener('submit', event => {
  event.preventDefault();
  const value = $('tv-text').value;
  if (value) command({type:'text',value}, 'Texto enviado. Confira o campo na TV.');
});
$('apps-form').addEventListener('submit', async event => {
  event.preventDefault();
  try { await post('/api/apps', {spotify:$('spotify').value.trim(),youtube:$('youtube').value.trim(),netflix:$('netflix').value.trim()}); feedback('IDs salvos no Windows.'); }
  catch (error) { feedback(error.message); }
});
$('pair-form').addEventListener('submit', async event => {
  event.preventDefault();
  try { await post('/api/pair', {pin:$('pin').value}, false); $('pin').value=''; $('pair-message').textContent=''; await refresh(); }
  catch (error) { $('pair-message').textContent = error.message; }
});
document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });
refresh();
setInterval(() => { if (!document.hidden && !$('remote').hidden) refresh(); }, 15000);
