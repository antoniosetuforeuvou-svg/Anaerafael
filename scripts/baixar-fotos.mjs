// Baixa todas as fotos do bucket para a pasta ./fotos-baixadas
// Uso (no seu computador, NÃO no site):
//   npm install @supabase/supabase-js
//   SUPABASE_URL=https://xxx.supabase.co SUPABASE_SERVICE_KEY=sua-service-role node scripts/baixar-fotos.mjs
// A service_role key dá acesso total: nunca coloque no config.js nem no GitHub.
import { createClient } from "@supabase/supabase-js";
import { mkdir, writeFile } from "node:fs/promises";

const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);
await mkdir("fotos-baixadas", { recursive: true });

let offset = 0, total = 0;
for (;;) {
  const { data, error } = await sb.storage.from("fotos").list("", { limit: 100, offset, sortBy: { column: "created_at", order: "asc" } });
  if (error) throw error;
  if (!data.length) break;
  for (const obj of data) {
    const { data: blob, error: e } = await sb.storage.from("fotos").download(obj.name);
    if (e) { console.error("Falhou:", obj.name, e.message); continue; }
    await writeFile(`fotos-baixadas/${obj.name}`, Buffer.from(await blob.arrayBuffer()));
    total++;
  }
  offset += data.length;
}
console.log(`${total} fotos salvas em ./fotos-baixadas`);
