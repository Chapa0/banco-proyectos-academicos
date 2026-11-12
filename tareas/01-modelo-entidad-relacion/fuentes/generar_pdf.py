"""Genera el informe explicado de la entrega 01 en formato A3 horizontal uniforme."""
from __future__ import annotations
import hashlib
import io
import json
import sys
from pathlib import Path

import fitz
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A3, landscape
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph, Table, TableStyle

sys.stdout.reconfigure(encoding='utf-8')
BASE = Path(__file__).resolve().parent.parent
MODEL = BASE/'fuentes/modelo.json'
COPY = BASE/'fuentes/explicaciones.json'
DATA = json.loads(MODEL.read_text(encoding='utf-8'))
TEXT = json.loads(COPY.read_text(encoding='utf-8'))
ENTITIES = {e['id']:e for e in DATA['entidades']}
AREAS = {a['id']:a for a in DATA['areas']}
W,H = landscape(A3)
M = 48
CW = W-2*M
INK, MUTED, TEAL, LINE = '#163249','#536777','#12666B','#D8E2E8'
PALE = '#F3F7F8'
TOTAL = 15
PLACEMENTS = []
BOUNDS = []
PAGE = 0


def fonts():
    paths = [(Path('C:/Windows/Fonts/arial.ttf'),Path('C:/Windows/Fonts/arialbd.ttf')),
             (Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'),
              Path('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'))]
    for regular,bold in paths:
        if regular.exists() and bold.exists():
            pdfmetrics.registerFont(TTFont('Body',str(regular)))
            pdfmetrics.registerFont(TTFont('BodyBold',str(bold)))
            pdfmetrics.registerFontFamily('Body',normal='Body',bold='BodyBold')
            return
    raise RuntimeError('Se requieren fuentes Arial o DejaVu Sans.')


def validate():
    assert len(ENTITIES)==21 and len(DATA['relaciones'])==37
    fks={(e['id'],f) for e in DATA['entidades'] for f,k in e['campos'] if 'FK' in k}
    refs={(r[1],r[2]) for r in DATA['relaciones']}
    assert fks==refs and len(refs)==37


fonts()
validate()
styles={}
for name,size,leading,font,color in [
    ('body',12,17,'Body',INK),('lead',13,19,'Body',MUTED),
    ('small',10,14,'Body',MUTED),('tiny',9,12,'Body',MUTED),
    ('heading',15,20,'BodyBold',INK),('card',11.2,15.5,'Body',INK),
    ('cell',10.5,14.5,'Body',INK),('th',10.5,14.5,'BodyBold','#FFFFFF')]:
    styles[name]=ParagraphStyle(name,fontName=font,fontSize=size,leading=leading,
        textColor=colors.HexColor(color),alignment=TA_LEFT)


def para(c,text,x,y,width,style='body',limit=None):
    q=Paragraph(text,styles[style])
    _,height=q.wrap(width,H)
    if limit is not None and height>limit+.2:
        raise ValueError(f'Página {PAGE}: párrafo excede su marco ({height:.1f}>{limit}): {text[:65]}')
    if y+height>H-42:
        raise ValueError(f'Página {PAGE}: texto demasiado bajo: {text[:65]}')
    q.drawOn(c,x,H-y-height)
    BOUNDS.append([PAGE,round(x,2),round(y,2),round(width,2),round(height,2)])
    return y+height


def box(c,x,y,width,height,fill=PALE,stroke=None,radius=9):
    c.setFillColor(colors.HexColor(fill))
    c.setStrokeColor(colors.HexColor(stroke or fill))
    c.roundRect(x,H-y-height,width,height,radius,fill=1,stroke=bool(stroke))


def start(c,number,kicker,title=None,lead=None):
    global PAGE
    PAGE=number
    c.setFillColor(colors.white);c.rect(0,0,W,H,fill=1,stroke=0)
    c.setFillColor(colors.HexColor(TEAL));c.rect(0,H-7,W,7,fill=1,stroke=0)
    c.setFont('BodyBold',9);c.setFillColor(colors.HexColor(MUTED))
    c.drawString(M,H-31,'BANCO DE PROYECTOS ACADÉMICOS / ENTREGA 01')
    c.drawRightString(W-M,H-31,kicker.upper())
    c.setStrokeColor(colors.HexColor(LINE));c.line(M,41,W-M,41)
    c.setFont('Body',9);c.drawString(M,24,f'Revisión {TEXT["revision"]} · {TEXT["fecha"]}')
    c.drawRightString(W-M,24,f'{number:02d} / {TOTAL:02d}')
    if title:
        c.setFont('BodyBold',25);c.setFillColor(colors.HexColor(INK))
        c.drawString(M,H-78,title)
    if lead:
        para(c,lead,M,94,CW,'lead',43)


def finish(c):
    c.showPage()


def panel(c,title,body,x,y,width,height,accent=TEAL):
    box(c,x,y,width,height)
    c.setFillColor(colors.HexColor(accent))
    c.roundRect(x,y=H-y-height,width=4,height=height,radius=2,fill=1,stroke=0)
    para(c,title,x+17,y+14,width-34,'heading',24)
    para(c,body,x+17,y+45,width-34,'card',height-56)


def tab(c,rows,widths,y,fontsize=None):
    cell_style=styles['cell']
    if fontsize:
        cell_style=ParagraphStyle('localcell',parent=cell_style,fontSize=fontsize,leading=fontsize*1.38)
    cells=[[Paragraph(str(v),styles['th'] if i==0 else cell_style)
            for v in row] for i,row in enumerate(rows)]
    t=Table(cells,colWidths=widths,hAlign='LEFT')
    t.setStyle(TableStyle([
        ('VALIGN',(0,0),(-1,-1),'TOP'),
        ('BACKGROUND',(0,0),(-1,0),colors.HexColor(INK)),
        ('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white,colors.HexColor(PALE)]),
        ('LEFTPADDING',(0,0),(-1,-1),11),('RIGHTPADDING',(0,0),(-1,-1),11),
        ('TOPPADDING',(0,0),(-1,-1),9),('BOTTOMPADDING',(0,0),(-1,-1),9),
        ('LINEBELOW',(0,0),(-1,-1),.4,colors.HexColor(LINE))]))
    width,height=t.wrap(CW,H)
    if height>H-60-y:
        raise ValueError(f'Página {PAGE}: tabla excede marco {height:.1f}>{H-60-y:.1f}')
    t.drawOn(c,M,H-y-height)
    BOUNDS.append([PAGE,M,y,round(width,2),round(height,2)])
    return y+height


def diagram(c,view,x,y,width,height):
    box(c,x,y,width,height,fill='#FFFFFF',stroke=LINE)
    PLACEMENTS.append({'pagina':PAGE,'vista':view,'rect':[x+10,y+10,x+width-10,y+height-10]})


def cover(c):
    start(c,1,'Presentación e índice')
    c.setFont('BodyBold',11);c.setFillColor(colors.HexColor(TEAL))
    c.drawString(M,H-92,'PRIMERA ENTREGA / DISEÑO DE DATOS')
    c.setFont('BodyBold',40);c.setFillColor(colors.HexColor(INK))
    c.drawString(M,H-150,'Modelo')
    c.drawString(M,H-198,'entidad-relación')
    para(c,'Banco de proyectos académicos',M,220,655,'heading',30)
    para(c,TEXT['objetivo'],M,263,635,'lead',90)
    para(c,'El informe explica primero el funcionamiento y la notación; después presenta el modelo integral, sus cinco áreas y un ejemplo que conecta todos los procesos.',M,350,635,'body',90)
    para(c,'Alcance: usuarios, empresas, proyectos, habilidades, solicitudes y asignaciones. Calificaciones, entregables, convenios y pagos quedan para una etapa posterior.',M,410,635,'small',34)
    y=452
    for a in DATA['areas']:
        box(c,M,y,635,49,fill=a['fondo'])
        n=sum(e['area']==a['id'] for e in DATA['entidades'])
        c.setFont('BodyBold',12);c.setFillColor(colors.HexColor(a['color']))
        c.drawString(M+15,H-y-22,a['titulo'])
        c.setFont('Body',10);c.drawRightString(M+618,H-y-22,f'{n} entidades')
        y+=57
    x=735;width=W-M-x
    box(c,x,91,width,653)
    para(c,'Contenido del informe',x+22,116,width-44,'heading',25)
    rows=[('Funcionamiento del sistema','02'),('Cómo leer el modelo','03'),
          ('Modelo general completo','04'),('Cinco áreas explicadas','05-09'),
          ('Caso práctico integrado','10'),('Catálogo de entidades','11-13'),
          ('Reglas y su justificación','14'),('Definiciones y fuentes','15')]
    y=168
    for title,page in rows:
        para(c,title,x+22,y,width-100,'body',40)
        c.setFont('BodyBold',12);c.setFillColor(colors.HexColor(TEAL))
        c.drawRightString(x+width-22,H-y-14,page)
        c.setStrokeColor(colors.HexColor(LINE));c.line(x+22,H-y-34,x+width-22,H-y-34)
        y+=55
    para(c,'21 entidades<br/>37 relaciones de referencia<br/>5 áreas del mismo sistema',x+22,643,width-44,'body',70)
    finish(c)


def operation(c):
    start(c,2,'01 / Contexto','Cómo funciona el sistema',
          'Dos procesos de participación independientes, unidos por las autorizaciones y el acompañamiento.')
    gap=13;cw=(CW-3*gap)/4
    actors=[
        ('Administrador','Crea cuentas, revisa la publicación y resuelve las asignaciones. Conserva fecha, resultado y justificación.'),
        ('Empresa','Propone proyectos, consulta sus candidatos y registra evaluaciones y recomendaciones.'),
        ('Alumno','Completa su perfil, declara habilidades, presenta candidaturas y consulta sus resultados.'),
        ('Profesor','Registra su perfil, solicita dirigir proyectos y consulta solicitudes, direcciones y carga.')]
    for i,(title,body) in enumerate(actors):
        panel(c,title,body,M+i*(cw+gap),145,cw,135)
    para(c,'Punto de partida: un proyecto publicado y disponible',M,300,CW,'heading',25)
    gap=22;cw=(CW-gap)/2
    branches=[
        ('Rama del alumno',[
            'El alumno presenta una Candidatura.',
            'La empresa evalúa esa candidatura y puede recomendar al candidato.',
            'El administrador resuelve la participación del alumno.',
            'Solo una aprobación válida origina AsignacionAlumno.']),
        ('Rama del profesor',[
            'El profesor presenta una SolicitudDireccion con su justificación.',
            'El administrador revisa la solicitud y los límites docentes aplicables.',
            'El administrador resuelve la participación del profesor por separado.',
            'Solo una aprobación válida origina AsignacionDireccion.'])]
    for i,(title,steps) in enumerate(branches):
        x=M+i*(cw+gap)
        box(c,x,337,cw,319)
        para(c,title,x+20,353,cw-40,'heading',30)
        y=397
        for j,step in enumerate(steps,1):
            c.setFont('BodyBold',12);c.setFillColor(colors.HexColor(TEAL))
            c.drawString(x+20,H-y-13,str(j).zfill(2))
            para(c,step,x+53,y,cw-74,'body',48)
            y+=57
    panel(c,'Dónde se encuentran las dos ramas',
          'Acompanamiento identifica qué dirección acompaña a qué participación de alumno del mismo proyecto. Auditoría y notificaciones conservan y comunican los cambios pertinentes. El ejemplo no fija el orden institucional obligatorio ni las condiciones de inicio todavía pendientes.',
          M,681,CW,99)
    finish(c)


def reading(c):
    start(c,3,'02 / Notación','Cómo leer el modelo',
          'Las líneas representan relaciones de datos; no indican el orden cronológico de las operaciones.')
    rows=[['Concepto','Cómo se interpreta'],
          ['Entidad','Concepto sobre el que se guarda información: Empresa, Proyecto o Candidatura.'],
          ['Atributo','Dato que describe una entidad; por ejemplo, titulo en Proyecto.'],
          ['PK','Clave primaria: identifica un registro. Varios campos PK forman una sola clave compuesta.'],
          ['FK','Clave foránea: apunta a un registro de otra entidad. Proyecto.empresa_id identifica a su empresa.'],
          ['UK / UK*','Unicidad propuesta. En RevisionProyecto, UK* combina proyecto_id y numero.'],
          ['? / XOR','? indica referencia opcional. XOR exige que exactamente un objeto de decisión esté informado.']]
    tab(c,rows,[125,418],147)
    x=635;width=W-M-x
    para(c,'Una relación leída en dos sentidos',x,147,width,'heading',30)
    box(c,x,194,170,84,fill='#EAF5F4',stroke='#12666B')
    box(c,x+width-170,194,170,84,fill='#EDF3FB',stroke='#245997')
    para(c,'<b>Empresa</b><br/>PK: id',x+18,212,140,'body',55)
    para(c,'<b>Proyecto</b><br/>FK: empresa_id',x+width-152,212,140,'body',55)
    c.setStrokeColor(colors.HexColor(MUTED));c.line(x+174,H-235,x+width-174,H-235)
    c.line(x+width-180,H-231,x+width-174,H-235);c.line(x+width-180,H-239,x+width-174,H-235)
    para(c,'1 / 0..N',x+182,208,width-364,'small',35)
    para(c,'En la etiqueta A / B, A corresponde al origen de la flecha y B al destino. Cada proyecto pertenece a una empresa; una empresa puede conservar cero o varios proyectos.',x,303,width,'body',78)
    tab_rows=[['Símbolo','Cantidad de registros'],
              ['1','Exactamente uno'],['0..1','Ninguno o uno'],
              ['0..N','Ninguno o varios'],['1..N','Uno o varios']]
    # La tabla derecha mantiene el mismo ancho que su panel.
    cells=[[Paragraph(v,styles['th'] if i==0 else styles['cell']) for v in r] for i,r in enumerate(tab_rows)]
    t=Table(cells,colWidths=[112,width-112])
    t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor(INK)),
        ('VALIGN',(0,0),(-1,-1),'TOP'),('TOPPADDING',(0,0),(-1,-1),10),
        ('BOTTOMPADDING',(0,0),(-1,-1),10),('LEFTPADDING',(0,0),(-1,-1),12),
        ('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white,colors.HexColor(PALE)])]))
    _,th=t.wrap(width,H);t.drawOn(c,x,H-398-th)
    panel(c,'Historial no significa cupo simultáneo',
          'Una empresa conserva representantes anteriores y mantiene uno activo. De igual forma, 0..N solicitudes o asignaciones conserva el historial sin aprobar que todas permanezcan vigentes a la vez. Los máximos y estados aplicables se concretan en sus decisiones.',
          M,669,CW,111)
    finish(c)


def global_model(c):
    start(c,4,'03 / Modelo integral','Modelo general de todo el sistema',
          'Las 21 entidades y las 37 relaciones se presentan juntas. Los atributos completos se consultan en el catálogo.')
    diagram(c,'general',M,142,CW,572)
    x=M
    for a in DATA['areas']:
        c.setFillColor(colors.HexColor(a['color']));c.roundRect(x,H-743,12,12,3,fill=1,stroke=0)
        c.setFont('Body',9.5);c.setFillColor(colors.HexColor(INK))
        c.drawString(x+18,H-741,a['titulo'])
        x += [211,224,252,198,200][list(AREAS).index(a['id'])]
    para(c,'D-09: una empresa por cuenta y un representante activo por empresa. XOR: cada decisión resuelve exactamente un objeto. Las referencias opcionales se explican en la guía y en el área de control.',M,758,CW,'small',30)
    finish(c)


def area(c,i,view):
    a=AREAS[view['id']];text=TEXT['areas'][view['id']]
    start(c,5+i,f'04 / Área {i+1} de 5',view['titulo'],
          'La misma entidad conserva su identidad cuando aparece en otra vista. Se muestran sus claves y relaciones del área.')
    diagram(c,view['id'],M,143,CW,428)
    para(c,text['clave'],M+3,580,CW-6,'small',29)
    gap=16;cw=(CW-2*gap)/3
    panel(c,'Qué información organiza',text['proposito'],M,613,cw,173,a['color'])
    body='<br/>'.join(text['relaciones'])
    panel(c,'Cómo leer sus relaciones',body,M+cw+gap,613,cw,173,a['color'])
    panel(c,'Ejemplo ficticio',text['ejemplo'],M+2*(cw+gap),613,cw,173,a['color'])
    finish(c)


def example(c):
    start(c,10,'05 / Caso práctico','Un ejemplo que conecta las cinco áreas',
          'Nova propone un sistema de inventario; Elena representa a la empresa, Lucía es alumna y Raúl es profesor.')
    rows=[['Paso','Responsable','Qué sucede','Qué conserva el modelo']]
    rows += [[r[0],r[2],r[1],r[3]] for r in TEXT['caso']]
    bottom=tab(c,rows,[48,165,430,CW-643],146,10.8)
    panel(c,'Qué demuestra este recorrido',
          'Solicitar, evaluar, resolver y asignar son registros distintos. La solicitud docente no recibe la evaluación empresarial de la candidatura del alumno. El acompañamiento enlaza participaciones ya autorizadas. Es un recorrido ilustrativo; no impone el orden obligatorio de todas las operaciones ni las condiciones de inicio.',
          M,max(bottom+20,662),CW,113)
    finish(c)


def catalogs(c):
    all_entities=DATA['entidades']
    for chunk in range(3):
        page=11+chunk
        start(c,page,'06 / Referencia',f'Catálogo de entidades · {chunk+1} de 3',
              'Responsabilidad, atributos y referencia funcional. Los campos PK y FK se conservan en la fuente editable.')
        rows=[['Entidad y área','Para qué sirve','Atributos y claves','Fuente']]
        for e in all_entities[chunk*7:(chunk+1)*7]:
            name=f"<b>{e['nombre']}</b><br/><font color='{AREAS[e['area']]['color']}'>{AREAS[e['area']]['titulo']}</font>"
            fields=', '.join(f"{field} [{key}]" if key else field for field,key in e['campos'])
            rows.append([name,e['descripcion'],fields,e['fuente']])
        tab(c,rows,[195,255,450,CW-900],148,11.3)
        finish(c)


def rules(c):
    start(c,14,'07 / Coherencia','Reglas de integridad y su propósito',
          'Estas condiciones explican qué debe preservar el futuro esquema PostgreSQL y qué problema evita cada regla.')
    rows=[['Regla','Condición','Por qué es necesaria']]+TEXT['reglas']
    tab(c,rows,[176,485,CW-661],145,10.4)
    finish(c)


def limits(c):
    start(c,15,'08 / Alcance y fuentes','Qué está acordado y qué falta concretar',
          'El modelo es una propuesta integral de diseño. Las decisiones abiertas permanecen identificadas sin convertirse en políticas aprobadas.')
    gap=18;cw=(CW-gap)/2
    panel(c,'Acuerdo D-09','El administrador crea las cuentas; cada empresa tiene un representante activo y cada cuenta empresarial se vincula a una sola empresa.',M,144,cw,96)
    panel(c,'Motor elegido: PostgreSQL','D-13 confirma el motor de datos. Esta entrega documenta entidades y relaciones; todavía no acredita DDL, migraciones ni restricciones ejecutadas.',M+cw+gap,144,cw,96)
    rows=[['Pregunta institucional','Referencia','Tratamiento en el modelo']]+TEXT['pendientes']
    end=tab(c,rows,[405,130,CW-535],262,10.5)
    y=end+23
    para(c,'Fuentes y trazabilidad',M,y,CW,'heading',25)
    para(c,'Fuente funcional: Proyecto.pdf, pp. 2-9. Identidad y perfiles: RF-01 a RF-07, RF-17 a RF-20 y RF-26. Proyectos: RF-08 a RF-13, RF-21, RF-27, RF-33 y RF-34. Participación: RF-22 a RF-25 y RF-28 a RF-32. Evaluación: RF-14 a RF-16. Revisión y asignación: RF-35 a RF-40. Historial, reportes y avisos: RF-06, RF-41 y RF-42. Los reportes se obtienen mediante consultas.',M,y+30,CW,'small',65)
    finish(c)


def build():
    stream=io.BytesIO()
    c=canvas.Canvas(stream,pagesize=(W,H),pageCompression=1)
    cover(c);operation(c);reading(c);global_model(c)
    for i,view in enumerate(DATA['vistas'][1:]):area(c,i,view)
    example(c);catalogs(c);rules(c);limits(c);c.save()
    result=fitz.open(stream=stream.getvalue(),filetype='pdf')
    assert len(result)==TOTAL
    placements=[]
    for item in PLACEMENTS:
        svg=BASE/'diagramas'/f"{item['vista']}.svg"
        with fitz.open(svg) as source:
            vector=fitz.open(stream=source.convert_to_pdf(),filetype='pdf')
        rect=fitz.Rect(item['rect'])
        result[item['pagina']-1].show_pdf_page(rect,vector,0,keep_proportion=True)
        scale=min(rect.width/vector[0].rect.width,rect.height/vector[0].rect.height)
        placements.append({**item,'escala':round(scale,4)})
        vector.close()
    sections=[[1,'Presentación e índice',1],[1,'Funcionamiento del sistema',2],
              [1,'Cómo leer el modelo',3],[1,'Modelo general completo',4]]
    for i,v in enumerate(DATA['vistas'][1:]):
        sections.append([1,v['titulo'],5+i])
    sections += [[1,'Caso práctico integrado',10],[1,'Catálogo de entidades',11],
                 [1,'Reglas de integridad',14],[1,'Definiciones pendientes y fuentes',15]]
    result.set_toc(sections)
    result.set_metadata({'title':'Modelo entidad-relación explicado - Banco de proyectos académicos',
        'author':'Proyecto académico','subject':'Entrega 01: modelo integral, áreas y explicación del sistema',
        'keywords':'modelo entidad relación, PostgreSQL, proyectos académicos',
        'creator':'ReportLab y PyMuPDF; diagramas SVG vectoriales'})
    output=BASE/'modelo-entidad-relacion.pdf'
    result.save(output,garbage=4,deflate=True)
    result.close()
    with fitz.open(output) as check:
        receipt={'archivo':output.name,'revision_editorial':TEXT['revision'],'fecha':TEXT['fecha'],
            'paginas':len(check),'formato':'A3 horizontal uniforme',
            'entidades':21,'relaciones_fk':37,'laminas_vectoriales':6,
            'secciones':sections,'ubicacion_diagramas':placements,
            'modelo_sha256':hashlib.sha256(MODEL.read_bytes()).hexdigest(),
            'explicaciones_sha256':hashlib.sha256(COPY.read_bytes()).hexdigest(),
            'pdf_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
            'dimensiones_pt':[[round(p.rect.width,2),round(p.rect.height,2)] for p in check]}
    (BASE/'fuentes/verificacion-pdf.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'pdf':str(output),'paginas':TOTAL,'formato':receipt['formato'],
                      'diagramas':placements},ensure_ascii=False,indent=2))


if __name__=='__main__':
    build()
