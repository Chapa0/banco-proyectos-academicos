/**
 * Regenera las seis vistas vectoriales desde modelo.json.
 * Uso: node generar_diagramas.mjs [ruta/al/modulo/@viz-js/viz/dist/viz.js]
 * Si @viz-js/viz está instalado junto al proyecto no hace falta el argumento.
 */
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');
const source = await readFile(resolve(here, 'modelo.json'), 'utf8');
const model = JSON.parse(source);
const vizModule = process.argv[2] ? await import(pathToFileURL(resolve(process.argv[2])).href) : await import('@viz-js/viz');
const viz = await vizModule.instance();
const entities = new Map(model.entidades.map(e => [e.id, e]));
const areas = new Map(model.areas.map(a => [a.id, a]));
const escape = s => String(s).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const quote = s => JSON.stringify(String(s));
await mkdir(resolve(root, 'diagramas'), { recursive: true });
await mkdir(resolve(here, 'diagramas'), { recursive: true });

function shownFields(e, general) {
  if (general) return e.campos.filter(([, k]) => k.includes('PK'));
  return e.campos.filter(([, k]) => k.includes('PK') || k.includes('FK'));
}

function label(e, general) {
  const a = areas.get(e.area);
  const fields = shownFields(e, general);
  const rows = fields.map(([f, k], i) => `<TR><TD PORT="${f}" ALIGN="LEFT" CELLPADDING="4" BGCOLOR="${i%2 ? '#FFFFFF' : a.fondo}"><FONT FACE="Arial" POINT-SIZE="12" COLOR="${a.color}">${escape(k || ' ')}</FONT></TD><TD ALIGN="LEFT" CELLPADDING="4" BGCOLOR="${i%2 ? '#FFFFFF' : a.fondo}"><FONT FACE="Arial" POINT-SIZE="12" COLOR="#172838">${escape(f)}</FONT></TD></TR>`).join('');
  return `<<TABLE BORDER="1" CELLBORDER="0" CELLSPACING="0" CELLPADDING="0" COLOR="${a.color}"><TR><TD COLSPAN="2" PORT="header" ALIGN="LEFT" BGCOLOR="${a.color}" CELLPADDING="8"><FONT FACE="Arial" POINT-SIZE="15" COLOR="white"><B>${escape(e.nombre)}</B></FONT></TD></TR>${rows}</TABLE>>`;
}

function generalDot(relationships) {
  const lines = [
    'digraph ER {',
    'graph [rankdir=LR, compound=true, bgcolor="white", pad=.15, ranksep=.45, nodesep=.25, splines=polyline, newrank=true, outputorder=edgesfirst];',
    'node [shape=box, style="rounded,filled", fontname="Arial", fontsize=14, margin=".08,.06"];',
    'edge [color="#8795A1", fontcolor="#475569", fontname="Arial", fontsize=12, penwidth=.7, arrowsize=.5];'
  ];
  for (const area of model.areas) {
    lines.push(`subgraph cluster_${area.id} {label=${quote(area.titulo)}; color="${area.color}"; fillcolor="${area.fondo}"; style="rounded,filled"; fontname="Arial"; fontsize=16; fontcolor="${area.color}"; margin=12;`);
    for (const e of model.entidades.filter(e => e.area === area.id)) {
      const pk = e.campos.filter(([,k]) => k.includes('PK')).map(([f]) => f).join(', ');
      lines.push(`${e.id} [id=${quote('entity-'+e.id)}, fillcolor="white", color="${area.color}", label=${quote(e.nombre+'\nPK '+pk)}];`);
    }
    lines.push('}');
  }
  for (const [parent,child,field,pCard,cCard] of relationships) {
    const xor = entities.get(child).campos.find(([f]) => f === field)?.[1].includes('XOR');
    const metadata = ['autor_usuario_id','administrador_usuario_id','evaluador_usuario_id','actor_usuario_id','destinatario_usuario_id'].includes(field);
    lines.push(`${parent} -> ${child} [id=${quote('relation-'+parent+'-'+child+'-'+field)}, label=${quote(pCard+' / '+cCard)}, ${metadata ? 'constraint=false,' : ''} ${xor ? 'style=dashed, color="#A04358", fontcolor="#A04358",' : ''}];`);
  }
  lines.push('}');
  return lines.join('\n');
}

// Reparaciones locales de dos colisiones verificadas en la lámina general.
// Solo cambian la posición de sus textos; rutas, entidades y cardinalidades
// conservan exactamente la salida del motor. Si cambia la geometría de origen,
// se exige revisar la composición en vez de reutilizar un ajuste a ciegas.
const generalLabelRepairs = [
  {id:'relation-habilidad-alumno_habilidad-habilidad_id', expected:[507.18,-400.82], position:[458,-355]},
  {id:'relation-proyecto-solicitud_direccion-proyecto_id', expected:[507.18,-535.2], position:[540,-620]}
];
function repairGeneralLabels(svg) {
  const repaired = new Set();
  const output = svg.replace(/<g id="([^"]+)" class="edge">[\s\S]*?<\/g>/g, (group, encodedId) => {
    const id = encodedId.replaceAll('&#45;', '-');
    const repair = generalLabelRepairs.find(r => r.id === id);
    if (!repair) return group;
    const textTag = group.match(/<text\b[^>]*>/)?.[0];
    const x = Number(textTag?.match(/\bx="([^"]+)"/)?.[1]);
    const y = Number(textTag?.match(/\by="([^"]+)"/)?.[1]);
    if (Math.abs(x-repair.expected[0]) > .1 || Math.abs(y-repair.expected[1]) > .1)
      throw new Error(`La geometría de ${id} cambió; revisar el ajuste local de su etiqueta.`);
    const moved = textTag.replace(/\bx="[^"]+"/, `x="${repair.position[0]}"`)
      .replace(/\by="[^"]+"/, `y="${repair.position[1]}"`);
    repaired.add(id);
    return group.replace(textTag, moved);
  });
  if (repaired.size !== generalLabelRepairs.length)
    throw new Error('No se localizaron las dos etiquetas diagnosticadas del modelo general.');
  return output;
}
async function writeChanged(path, content) {
  const previous = await readFile(path, 'utf8').catch(e => { if (e.code === 'ENOENT') return null; throw e; });
  if (previous !== content) await writeFile(path, content);
}

const receipts = [];
for (const [index, view] of model.vistas.entries()) {
  const ids = view.entidades === 'todas' ? model.entidades.map(e => e.id) : view.entidades;
  const idSet = new Set(ids);
  const relationships = model.relaciones.filter(([a,b]) => idSet.has(a) && idSet.has(b));
  const general = view.id === 'general';
  const options = [
    'digraph ER {',
    `graph [rankdir=${general ? 'TB' : 'LR'}, bgcolor="white", pad="0.18", nodesep="0.30", ranksep="0.55", splines=polyline, outputorder=edgesfirst, fontname="Arial", fontsize=12, overlap=false, newrank=true];`,
    'node [shape=plain, fontname="Arial"];',
    'edge [fontname="Arial", fontsize=12, fontcolor="#475569", color="#758494", penwidth=0.9, arrowsize=0.55, arrowhead=normal];'
  ];
  for (const id of ids) options.push(`${id} [id=${quote('entity-'+id)}, label=${label(entities.get(id), general)}];`);
  // Las alineaciones fijan la lectura de izquierda a derecha sin alterar relaciones.
  const ranks = general ? [
    ['usuario','empresa','habilidad','criterio_evaluacion'],
    ['alumno','profesor','representacion_empresa','proyecto','evento_auditoria'],
    ['alumno_habilidad','proyecto_habilidad','revision_proyecto','candidatura','solicitud_direccion','notificacion'],
    ['evaluacion_candidato','decision_administrativa'],
    ['detalle_evaluacion','asignacion_alumno','asignacion_direccion'],
    ['acompanamiento']
  ] : [];
  for (const rank of ranks) options.push(`{rank=same; ${rank.join(';')};}`);
  for (const [i, [parent, child, field, pCard, cCard]] of relationships.entries()) {
    const pk = entities.get(parent).campos.find(([, k]) => k.includes('PK'))[0];
    const xor = entities.get(child).campos.find(([f]) => f === field)?.[1].includes('XOR');
    const nonConstraint = ['autor_usuario_id','administrador_usuario_id','evaluador_usuario_id','actor_usuario_id','destinatario_usuario_id'].includes(field);
    options.push(`${parent}${general ? '' : ':header:e'} -> ${child}${general ? '' : ':'+field+':w'} [id=${quote('relation-'+parent+'-'+child+'-'+field)}, label=${quote(pCard+' / '+cCard)}, ${xor ? 'style=dashed, color="#A04358", fontcolor="#A04358",' : ''} ${nonConstraint && general ? 'constraint=false,' : ''} weight=${nonConstraint ? 1 : 3}];`);
  }
  options.push('}');
  const dot = general ? generalDot(relationships) : options.join('\n');
  const name = view.id;
  const dotName = `${String(index).padStart(2,'0')}-${view.id}`;
  const result = viz.render(dot, { format: 'svg', engine: 'dot' });
  if (result.status !== 'success') throw new Error(JSON.stringify({view:view.id,errors:result.errors}));
  const svg = general ? repairGeneralLabels(result.output) : result.output;
  await writeChanged(resolve(here, 'diagramas', dotName+'.dot'), dot+'\n');
  await writeChanged(resolve(root, 'diagramas', name+'.svg'), svg);
  const size = svg.match(/viewBox="([^"]+)"/)[1].split(/\s+/).map(Number);
  receipts.push({vista:view.id,archivo:`diagramas/${name}.svg`,entidades:ids.length,relaciones:relationships.length,viewBox:size,fuenteMinimaPt:12,escalaEnMarco1090x570:Math.min(1090/size[2],570/size[3]),ajustesEtiquetas:general ? generalLabelRepairs : [],sha256:createHash('sha256').update(svg).digest('hex'),advertencias:result.errors});
  console.log(`${view.id}: ${ids.length} entidades, ${relationships.length} relaciones, ${size[2]} × ${size[3]} pt`);
}
await writeFile(resolve(here, 'verificacion-diagramas.json'), JSON.stringify({fecha:'27 de octubre de 2026',presentacion:'Compacta horizontal; claves y relaciones; atributos completos en catálogo',motor:'@viz-js/viz / Graphviz WASM',modeloSha256:createHash('sha256').update(source).digest('hex'),vistas:receipts},null,2)+'\n');
