# Fotos do casamento

Site estático onde cada convidado envia até 20 fotos. GitHub + Supabase + Vercel, tudo no plano gratuito.

## 1. Supabase
1. Crie um projeto em supabase.com (região São Paulo, se estiver no Brasil).
2. Abra o arquivo `supabase/schema.sql`, troque `TROQUE-ESTE-CODIGO` por um código seu (ex.: `ANAPEDRO26`).
3. No painel: SQL Editor (se já tinha rodado a versão anterior, rode este arquivo inteiro de novo) > New query > cole o arquivo inteiro > Run.
4. Em Project Settings > API, copie a Project URL e a chave anon/publishable.

## 2. Configuração
Edite `config.js` com a URL, a chave, os nomes do casal e a data.

## 3. GitHub e Vercel
1. Crie um repositório no GitHub e envie estes arquivos.
2. Na Vercel: Add New > Project > importe o repositório > Framework Preset: Other > Deploy.
3. Pronto: cada push no GitHub publica de novo sozinho.

## 4. QR code
Gere um QR code (qualquer gerador gratuito) apontando para:
`https://SEU-SITE.vercel.app/?c=SEU-CODIGO`
Quem abrir pelo QR code não precisa digitar o código.

## Login e bloqueio de contas extras
- O convidado digita só nome e sobrenome. Cada foto sai com "Foto de Fulano" gravado numa faixa embaixo.
- O mesmo nome sempre abre a mesma conta ("João Silva", "joao  silva" e "JOÃO SILVA" são iguais), então entrar de novo em outro celular ou aba anônima não ganha mais 20 fotos.
- Depois de entrar, o celular fica preso àquele nome (não há botão de trocar).
- O que não dá para impedir sem uma lista de convidados: alguém inventar um nome falso num segundo aparelho ou aba anônima.

## Limites do plano gratuito do Supabase
- 1 GB de arquivos: com a compressão do site (~300–500 KB por foto) cabem em torno de 2.000–3.000 fotos.
- 5 GB de tráfego por mês: cada visualização da galeria conta.
- O projeto pausa após 7 dias sem uso. Abra o site alguns dias antes da festa para garantir que está ativo.

## Depois da festa
Baixe tudo com `scripts/baixar-fotos.mjs` (instruções no próprio arquivo).
Para apagar uma foto: Supabase > Storage > fotos > selecione > Delete.
