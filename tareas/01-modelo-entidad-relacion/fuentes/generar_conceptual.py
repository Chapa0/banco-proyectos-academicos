"""Genera una exposición de tres páginas: Chen conceptual, flujo y explicación."""
from __future__ import annotations
import hashlib
import io
import json
from pathlib import Path
import sys

import fitz
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph, Table, TableStyle

from dibujar_chen import draw_chen

sys.stdout.reconfigure(encoding='utf-8')
BASE=Path(__file__).resolve().parent.parent
W,H=landscape(A4)
M=30
CW=W-2*M
INK='#000000'
MUTED='#333333'
LINE='#000000'
PAGE=0


def fonts():
    for regular,bold in [
        (Path('C:/Windows/Fonts/arial.ttf'),Path('C:/Windows/Fonts/arialbd.ttf')),
        (Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'),
         Path('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'))]:
        if regular.exists() and bold.exists():
            pdfmetrics.registerFont(TTFont('Body',str(regular)))
            pdfmetrics.registerFont(TTFont('BodyBold',str(bold)))
            pdfmetrics.registerFontFamily('Body',normal='Body',bold='BodyBold')
            return
    raise RuntimeError('Se requieren fuentes Arial o DejaVu Sans.')


fonts()
STYLES={
    'body':ParagraphStyle('body',fontName='Body',fontSize=10.2,leading=14,
                          textColor=colors.HexColor(INK)),
    'small':ParagraphStyle('small',fontName='Body',fontSize=9,leading=12,
                           textColor=colors.HexColor(MUTED)),
    'head':ParagraphStyle('head',fontName='BodyBold',fontSize=12,leading=16,
                          textColor=colors.HexColor(INK)),
    'label':ParagraphStyle('label',fontName='BodyBold',fontSize=10.2,leading=14,
                           textColor=colors.HexColor(INK)),
}


def para(c,text,x,y,width,style='body',limit=1000):
    p=Paragraph(text,STYLES[style]);_,height=p.wrap(width,H)
    if height>limit+.1 or y+height>H-24:
        raise ValueError(f'Página {PAGE}: texto fuera del marco: {text[:70]}')
    p.drawOn(c,x,H-y-height)
    return height


def rect(c,x,y,w,h):
    c.setFillColor(colors.white);c.setStrokeColor(colors.HexColor(LINE))
    c.setLineWidth(.8)
    c.rect(x,H-y-h,w,h,fill=1,stroke=1)


def text_center(c,text,x,y,width=140,size=10,bold=False):
    style=ParagraphStyle('center',parent=STYLES['body'],fontName='BodyBold' if bold else 'Body',
                         fontSize=size,leading=size+2,alignment=1)
    p=Paragraph(text.replace('\n','<br/>'),style)
    _,height=p.wrap(width,H)
    p.drawOn(c,x-width/2,H-y-height/2)


def header(c,page,title,lead=None):
    global PAGE
    PAGE=page
    c.setFillColor(colors.white);c.rect(0,0,W,H,fill=1,stroke=0)
    c.setFont('BodyBold',18);c.setFillColor(colors.HexColor(INK))
    c.drawString(M,H-39,title)
    if lead:para(c,lead,M,54,CW,'body',32)
    c.setFont('Body',8);c.setFillColor(colors.HexColor(MUTED))
    c.drawCentredString(W/2,14,str(page))


def node(c,text,x,y,w=170,h=35):
    rect(c,x-w/2,y-h/2,w,h)
    text_center(c,text,x,y,w-12,10)


def diamond(c,text,x,y,w=95,h=49):
    c.setStrokeColor(colors.HexColor(INK));c.setFillColor(colors.white)
    path=c.beginPath();path.moveTo(x,H-y+h/2);path.lineTo(x+w/2,H-y)
    path.lineTo(x,H-y-h/2);path.lineTo(x-w/2,H-y);path.close()
    c.drawPath(path,fill=1,stroke=1)
    text_center(c,text,x,y,w*.78,9.5,True)


def arrow(c,points,label=None,at=None):
    c.setLineWidth(.9);c.setStrokeColor(colors.HexColor(MUTED))
    path=c.beginPath();path.moveTo(points[0][0],H-points[0][1])
    for x,y in points[1:]:path.lineTo(x,H-y)
    c.drawPath(path)
    (x1,y1),(x2,y2)=points[-2:]
    import math
    angle=math.atan2(y2-y1,x2-x1)
    for delta in [-.50,.50]:
        x=x2-6*math.cos(angle+delta);y=y2-6*math.sin(angle+delta)
        c.line(x2,H-y2,x,H-y)
    if label:
        x,y=at
        c.setFont('BodyBold',8.8);c.setFillColor(colors.HexColor(INK))
        c.drawString(x,H-y,label)


def chen(c):
    header(c,1,'Modelo entidad-relación',
           'El sistema permite a las empresas proponer proyectos y a alumnos y profesores solicitar su participación.')
    result=draw_chen(c,W,H)
    para(c,'Notación Chen simplificada: rectángulo = entidad; rombo = relación; óvalo = atributo. 1 = uno; N/M = varios.',M,513,CW,'small',26)
    para(c,'Las cardinalidades incluyen el historial de participaciones. Las asignaciones de alumno y profesor requieren aprobaciones independientes.',M,538,CW,'small',26)
    c.showPage()
    return result


def flow(c):
    header(c,2,'Flujo principal del sistema',
           'La publicación se revisa antes de recibir solicitudes. Alumnos y profesores tienen procesos de participación independientes.')
    # Publicación del proyecto: proceso compartido por ambas ramas.
    node(c,'Empresa registra\ny envía el proyecto',110,137,148,36)
    node(c,'Administrador revisa\nla publicación',300,137,150,36)
    diamond(c,'¿Publicar?',480,137,94,48)
    node(c,'Proyecto publicado\ny disponible',690,137,162,36)
    arrow(c,[(184,137),(225,137)])
    arrow(c,[(375,137),(433,137)])
    arrow(c,[(527,137),(609,137)],'Sí',(557,128))
    arrow(c,[(480,161),(480,181)],'No',(487,176))
    node(c,'Corrección o rechazo',480,199,154,34)
    para(c,'Si se devuelve, la empresa corrige y reenvía.',383,220,211,'small',24)
    # Las dos ramas parten del mismo proyecto, sin imponerse orden entre ellas.
    arrow(c,[(690,155),(690,258),(600,258),(600,273)])
    arrow(c,[(690,244),(230,244),(230,273)])
    c.setFont('BodyBold',11);c.setFillColor(colors.HexColor(INK))
    c.drawString(156,H-263,'ALUMNO');c.drawString(526,H-263,'PROFESOR')
    node(c,'Alumno envía\nsu candidatura',230,291,190,36)
    node(c,'Profesor solicita\ndirigir el proyecto',600,291,190,36)
    arrow(c,[(230,309),(230,325)])
    arrow(c,[(600,309),(600,325)])
    node(c,'Empresa evalúa\ny recomienda',230,344,190,36)
    node(c,'Administrador revisa\nsolicitud y carga docente',600,344,190,36)
    arrow(c,[(230,362),(230,384)])
    arrow(c,[(600,362),(600,384)])
    diamond(c,'Administrador\n¿autoriza?',230,408,112,48)
    diamond(c,'Administrador\n¿autoriza?',600,408,112,48)
    arrow(c,[(174,408),(128,408)],'No',(147,400))
    arrow(c,[(656,408),(710,408)],'No',(677,400))
    node(c,'Rechazo:\nregistrar y avisar',79,408,98,42)
    node(c,'Rechazo:\nregistrar y avisar',760,408,98,42)
    arrow(c,[(230,432),(230,451)],'Sí',(238,446))
    arrow(c,[(600,432),(600,451)],'Sí',(608,446))
    node(c,'Asignación del alumno:\nregistrar y notificar',230,470,201,38)
    node(c,'Asignación de dirección:\nregistrar y notificar',600,470,201,38)
    arrow(c,[(230,489),(230,505),(270,505),(270,519)])
    arrow(c,[(600,489),(600,505),(570,505),(570,519)])
    node(c,'Cuando existan ambas participaciones, vincular alumno y profesor del mismo proyecto.',420,539,535,38)
    c.showPage()


def explanation(c):
    header(c,3,'Descripción del modelo')
    rows=[['Concepto','Qué representa'],
          ['Empresa y Proyecto','La organización propone una necesidad tecnológica; cada proyecto pertenece a una empresa.'],
          ['Alumno y Profesor','Participantes académicos. El alumno se postula y el profesor solicita dirigir proyectos.'],
          ['Candidatura','Solicitud del alumno: conserva su intención de participar y todavía no es una asignación.'],
          ['Solicitud de dirección','Solicitud del profesor: se revisa de forma independiente de la candidatura del alumno.'],
          ['Administrador','Crea las cuentas, revisa la publicación de proyectos y aprueba o rechaza las participaciones.'],
          ['Evalúa y resuelve','Relaciones distintas: la empresa recomienda; el administrador registra decisión, fecha y motivo.'],
          ['Participa y dirige','Relaciones que representan las participaciones autorizadas; se formalizan por separado.']]
    cells=[[Paragraph(v,STYLES['label'] if i==0 or j==0 else STYLES['body']) for j,v in enumerate(row)] for i,row in enumerate(rows)]
    t=Table(cells,colWidths=[168,CW-168])
    t.setStyle(TableStyle([('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),0),
        ('RIGHTPADDING',(0,0),(-1,-1),9),('TOPPADDING',(0,0),(-1,-1),7),
        ('BOTTOMPADDING',(0,0),(-1,-1),7)]))
    _,height=t.wrap(CW,H)
    if height>300:raise ValueError(f'La tabla de explicación ocupa demasiado: {height}')
    t.drawOn(c,M,H-70-height)
    y=70+height+24
    para(c,'Ejemplo',M,y,CW,'head',18)
    para(c,'Una empresa propone un sistema de inventario. Lucía se postula y el profesor Raúl solicita dirigirlo. La empresa evalúa a Lucía y el administrador resuelve cada solicitud por separado. Si ambas se aprueban, se registran las asignaciones y se vincula a Lucía con su profesor dentro del proyecto.',M,y+23,CW,'body',44)
    y+=83
    para(c,'Aspectos por definir',M,y,CW,'head',18)
    para(c,'Los cupos, la organización de equipos y las condiciones de inicio aún deben definirse. También debe confirmarse si la evaluación empresarial es obligatoria antes de autorizar. El flujo muestra una secuencia posible.',M,y+23,CW,'body',44)
    c.showPage()


def build():
    stream=io.BytesIO();c=canvas.Canvas(stream,pagesize=(W,H),pageCompression=1)
    info=chen(c);flow(c);explanation(c);c.save()
    data=stream.getvalue();pdf=fitz.open(stream=data,filetype='pdf')
    assert len(pdf)==3
    pdf.set_toc([[1,'Modelo conceptual Chen',1],[1,'Flujo principal',2],[1,'Interpretación y ejemplo',3]])
    pdf.set_metadata({'title':'Modelo entidad-relación y flujo del sistema',
        'author':'Proyecto académico','subject':'Entrega breve para exposición: modelo conceptual y funcionamiento',
        'keywords':'Chen, modelo conceptual, proyectos académicos, flujo',
        'creator':'ReportLab y PyMuPDF; diagramas vectoriales'})
    output=BASE/'modelo-conceptual-y-flujo.pdf';pdf.save(output,garbage=4,deflate=True)
    pdf.close()
    with fitz.open(output) as check:
        receipt={'archivo':output.name,'fecha':'27 de octubre de 2026',
            'paginas':len(check),'formato':'A4 horizontal uniforme',
            'chen':info,'pdf_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
            'dimensiones_pt':[[round(p.rect.width,2),round(p.rect.height,2)] for p in check],
            'modelo_logico_sha256':hashlib.sha256((BASE/'fuentes/modelo.json').read_bytes()).hexdigest()}
    (BASE/'fuentes/verificacion-conceptual.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(receipt,ensure_ascii=False,indent=2))


if __name__=='__main__':build()
