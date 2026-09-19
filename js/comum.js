import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";
import { SUPABASE_URL, SUPABASE_KEY, CASAL, DATA } from "../config.js";

export const supabase = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { persistSession: false },
});

export function ler(chave) {
  try { return JSON.parse(localStorage.getItem(chave)); } catch { return null; }
}
export function salvar(chave, valor) {
  try {
    if (valor == null) localStorage.removeItem(chave);
    else localStorage.setItem(chave, JSON.stringify(valor));
  } catch { /* navegador sem storage: segue só na memória */ }
}

// O código vem no link do QR code (?c=CODIGO) e fica guardado no aparelho.
export function lerCodigo() {
  const url = new URL(location.href);
  const c = url.searchParams.get("c");
  if (c) {
    salvar("casamento:codigo", c);
    url.searchParams.delete("c");
    history.replaceState(null, "", url);
    return c;
  }
  return ler("casamento:codigo");
}

export function urlPublica(caminho) {
  return supabase.storage.from("fotos").getPublicUrl(caminho).data.publicUrl;
}

export function cabecalho() {
  document.querySelectorAll("[data-casal]").forEach((el) => (el.textContent = CASAL));
  document.querySelectorAll("[data-data]").forEach((el) => (el.textContent = DATA));
  document.title = `${CASAL} — fotos`;
}

export function mensagemErro(err) {
  const m = String(err?.message || err || "");
  if (m.includes("codigo_invalido")) return "Código do casamento inválido. Confira o link do convite ou o QR code.";
  if (m.includes("limite_atingido")) return "Você já enviou o máximo de fotos.";
  if (m.includes("nome_incompleto")) return "Digite seu nome e sobrenome.";
  if (m.includes("convidado_invalido")) return "Seu cadastro não foi encontrado. Digite seu nome de novo.";
  if (m.includes("Failed to fetch") || m.includes("NetworkError")) return "Sem conexão. Verifique a internet e tente de novo.";
  return "Não foi possível concluir. Tente de novo em instantes.";
}

async function carregarImagem(fonte) {
  // Já é um quadro desenhável (vídeo da câmera, canvas ou bitmap)? Usa direto.
  if (fonte && !(fonte instanceof Blob)) return fonte;
  if ("createImageBitmap" in window) {
    try { return await createImageBitmap(fonte); } catch { /* tenta o método antigo */ }
  }
  return new Promise((res, rej) => {
    const img = new Image();
    const url = URL.createObjectURL(fonte);
    img.onload = () => { URL.revokeObjectURL(url); res(img); };
    img.onerror = () => { URL.revokeObjectURL(url); rej(new Error("formato_nao_suportado")); };
    img.src = url;
  });
}

let fontes;
function carregarFontes() {
  fontes ??= Promise.all([
    document.fonts.load('italic 500 48px "Cormorant Garamond"'),
    document.fonts.load('500 24px "Albert Sans"'),
  ]).catch(() => {});
  return fontes;
}

// Faixa branca embaixo da foto: "Foto de Fulano" à esquerda, o casal à direita.
function desenharAssinatura(ctx, largura, topo, altura, nome) {
  ctx.fillStyle = "#FFFFFF";
  ctx.fillRect(0, topo, largura, altura);
  const margem = Math.round(altura * 0.4);
  const meio = topo + altura / 2;
  ctx.textBaseline = "middle";

  ctx.font = `500 ${Math.round(altura * 0.24)}px "Albert Sans", sans-serif`;
  const casalLarg = ctx.measureText(CASAL).width;

  let tam = Math.round(altura * 0.44);
  const texto = `Foto de ${nome}`;
  const cabe = (comCasal) => {
    ctx.font = `italic 500 ${tam}px "Cormorant Garamond", Georgia, serif`;
    const livre = largura - margem * 2 - (comCasal ? casalLarg + margem : 0);
    return ctx.measureText(texto).width <= livre;
  };
  let mostrarCasal = true;
  while (!cabe(mostrarCasal) && tam > altura * 0.3) tam--;
  if (!cabe(mostrarCasal)) { mostrarCasal = false; while (!cabe(false) && tam > 10) tam--; }

  ctx.fillStyle = "#1E2733";
  ctx.textAlign = "left";
  ctx.fillText(texto, margem, meio);

  if (mostrarCasal) {
    ctx.font = `500 ${Math.round(altura * 0.24)}px "Albert Sans", sans-serif`;
    ctx.fillStyle = "#8A7442";
    ctx.textAlign = "right";
    ctx.fillText(CASAL, largura - margem, meio);
  }
}

// Reduz para no máx. 1600px, JPEG ~80% (250–500 KB) e grava a assinatura.
export async function comprimir(file, { assinatura = "", maximo = 1600, qualidade = 0.8 } = {}) {
  const [img] = await Promise.all([carregarImagem(file), carregarFontes()]);
  const w0 = img.videoWidth || img.naturalWidth || img.width;
  const h0 = img.videoHeight || img.naturalHeight || img.height;
  const escala = Math.min(1, maximo / Math.max(w0, h0));
  const w = Math.round(w0 * escala), h = Math.round(h0 * escala);
  const faixa = assinatura ? Math.round(Math.max(56, Math.min(w, h) * 0.09)) : 0;

  const canvas = document.createElement("canvas");
  canvas.width = w; canvas.height = h + faixa;
  const ctx = canvas.getContext("2d");
  ctx.drawImage(img, 0, 0, w, h);
  img.close?.();
  if (faixa) desenharAssinatura(ctx, w, h, faixa, assinatura);

  return new Promise((res, rej) =>
    canvas.toBlob((b) => (b ? res(b) : rej(new Error("falha_compressao"))), "image/jpeg", qualidade)
  );
}
