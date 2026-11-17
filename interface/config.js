// Cole aqui os endereços das Function URLs (com a barra final, como o console mostra).
const CONFIG = {
  URL_SOLICITAR: "https://efqirukl3zqjr4m5jsgcpp6fvm0aojkn.lambda-url.us-east-1.on.aws/",
  URL_CADASTRAR: "https://ospxtnhup4yyinb24sbsh3pkfe0ctbmm.lambda-url.us-east-1.on.aws/",
  // Opcional: Function URL da Lambda Listar (lambda/listar.py). Deixe vazio se não existir.
  URL_LISTAR: "https://e6chudhc3wpx5iowwzbhacv7uy0dhddu.lambda-url.us-east-1.on.aws/",
};

async function chamar(url, corpo) {
  const resp = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(corpo),
  });
  let dados = {};
  try { dados = await resp.json(); } catch (_) {}
  return { status: resp.status, dados };
}

function mostrar(el, tipo, texto) {
  el.className = "msg " + tipo;
  el.textContent = texto;
}
