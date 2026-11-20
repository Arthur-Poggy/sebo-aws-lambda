const CONFIG = {
  URL_SOLICITAR: "https://cjecx4oy7xml6a33i5taieolf40hnjvx.lambda-url.us-east-1.on.aws/",
  URL_CADASTRAR: "https://emfpf6gfsih6ueqx6glhma3ywy0cmsrf.lambda-url.us-east-1.on.aws/",
  URL_LISTAR: "https://utd6drrf3vi5hjl7ztk4pr5lum0vclfj.lambda-url.us-east-1.on.aws/",
  URL_INSCREVER: "https://fid2owdm53gaeegtmryrbpm54e0nscft.lambda-url.us-east-1.on.aws/",
};

async function chamar(url, corpo) {
  const resp = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(corpo),
  });
  const dados = await resp.json().catch(() => ({}));
  return { status: resp.status, dados };
}

async function listarLivros() {
  const resp = await fetch(CONFIG.URL_LISTAR);
  if (!resp.ok) throw new Error("HTTP " + resp.status);
  const dados = await resp.json();
  return dados.livros;
}

function mostrar(el, tipo, texto) {
  el.className = "msg " + tipo;
  el.textContent = texto;
}
