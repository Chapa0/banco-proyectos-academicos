"""Vista conceptual Chen principal, dibujada como vectores de ReportLab.

La fuente lógica de 21 entidades no se modifica. Los rombos de evaluación,
resolución y participación resumen relaciones del negocio, no pasos temporales.
"""
from reportlab.lib import colors

ENTITIES = [
    ('empresa', 'Empresa', 420, 140, 112, 34),
    ('proyecto', 'Proyecto', 420, 270, 112, 36),
    ('alumno', 'Alumno', 100, 270, 104, 34),
    ('profesor', 'Profesor', 740, 270, 104, 34),
    ('candidatura', 'Candidatura', 255, 370, 104, 34),
    ('solicitud', 'Solicitud de\ndirección', 585, 370, 116, 38),
    ('administrador', 'Administrador', 420, 475, 132, 36),
]

RELATIONS = [
    ('propone', 'propone', 420, 205, 84, 48, ('empresa', 'proyecto')),
    ('evalua', 'evalúa', 255, 140, 90, 48, ('empresa', 'candidatura')),
    ('presenta_candidatura', 'presenta', 145, 370, 76, 46, ('alumno', 'candidatura')),
    ('corresponde_candidatura', 'corresponde', 320, 320, 90, 48, ('candidatura', 'proyecto')),
    ('presenta_direccion', 'presenta', 695, 370, 76, 46, ('profesor', 'solicitud')),
    ('corresponde_direccion', 'corresponde', 520, 320, 90, 48, ('solicitud', 'proyecto')),
    ('resuelve_candidatura', 'resuelve', 255, 475, 90, 48, ('administrador', 'candidatura')),
    ('resuelve_direccion', 'resuelve', 585, 475, 90, 48, ('administrador', 'solicitud')),
    ('participa', 'participa', 255, 270, 90, 48, ('alumno', 'proyecto')),
    ('dirige', 'dirige', 585, 270, 90, 48, ('profesor', 'proyecto')),
]

ATTRIBUTES = [
    ('matricula', 'matrícula', 100, 216, 45, 14, 'alumno'),
    ('especialidad', 'especialidad', 740, 216, 50, 14, 'profesor'),
]

# Trazados en coordenadas desde el borde superior. Cada entrada conserva los
# extremos de una relación y su cardinalidad máxima (histórica).
LINKS = [
    ('propone_empresa', [(420,157),(420,181)], ('1',433,168)),
    ('propone_proyecto', [(420,229),(420,252)], ('N',433,241)),
    ('evalua_empresa', [(364,140),(300,140)], ('1',337,130)),
    ('evalua_candidatura', [(210,140),(180,140),(180,330),(225,330),(225,353)], ('N',214,343)),
    ('presenta_alumno', [(100,287),(100,370),(107,370)], ('1',112,309)),
    ('presenta_candidatura', [(183,370),(203,370)], ('N',193,359)),
    ('corresponde_candidatura', [(255,353),(255,320),(275,320)], ('N',244,338)),
    ('corresponde_proyecto_alumno', [(365,320),(390,320),(390,288)], ('1',379,300)),
    ('presenta_profesor', [(740,287),(740,370),(733,370)], ('1',752,309)),
    ('presenta_solicitud', [(657,370),(643,370)], ('N',650,359)),
    ('corresponde_solicitud', [(585,351),(585,320),(565,320)], ('N',596,338)),
    ('corresponde_proyecto_profesor', [(475,320),(450,320),(450,288)], ('1',461,300)),
    ('resuelve_admin_alumno', [(354,475),(300,475)], ('N',329,463)),
    ('resuelve_candidatura', [(255,451),(255,387)], ('M',244,416)),
    ('resuelve_admin_profesor', [(486,475),(540,475)], ('N',513,463)),
    ('resuelve_solicitud', [(585,451),(585,389)], ('M',596,416)),
    ('participa_alumno', [(152,270),(210,270)], ('M',167,258)),
    ('participa_proyecto', [(300,270),(364,270)], ('N',337,258)),
    ('dirige_proyecto', [(476,270),(540,270)], ('M',510,258)),
    ('dirige_profesor', [(630,270),(688,270)], ('N',661,258)),
]


def draw_chen(c, width=841.89, height=595.28):
    """Dibuja solo la figura, en x30..812 y top110..500 de A4 horizontal.

    El canvas debe tener registradas las fuentes Body y BodyBold. Devuelve
    metadatos que permiten contrastar objetos, cardinalidades y límites.
    """
    line = colors.black
    ink = colors.black

    def path(points, color=line, thickness=.95):
        c.setStrokeColor(color)
        c.setLineWidth(thickness)
        p = c.beginPath()
        p.moveTo(points[0][0], height-points[0][1])
        for x,y in points[1:]: p.lineTo(x,height-y)
        c.drawPath(p,stroke=1,fill=0)

    def centered(text,x,y,font='Body',size=10.5,color=ink):
        c.setFillColor(color)
        c.setFont(font,size)
        parts=text.split('\n')
        step=size+2
        for i,part in enumerate(parts):
            baseline=y+(i-(len(parts)-1)/2)*step+size*.34
            c.drawCentredString(x,height-baseline,part)

    c.saveState()
    # Conexiones primero: no se superponen sobre cajas ni etiquetas.
    for ident,points,_ in LINKS:
        path(points,line,1.0)
    path([(100,253),(100,230)],line,.85)
    path([(740,253),(740,230)],line,.85)

    # Un único cruce: interrupción del tramo vertical, sin punto de unión.
    # El tramo horizontal de Alumno--participa permanece continuo.
    c.setFillColor(colors.white)
    c.rect(177.8,height-275.2,4.4,10.4,stroke=0,fill=1)
    path([(175.5,270),(184.5,270)],line,1.0)

    for _,label,x,y,w,h in ENTITIES:
        c.setFillColor(colors.white)
        c.setStrokeColor(line)
        c.setLineWidth(1.15)
        c.rect(x-w/2,height-y-h/2,w,h,stroke=1,fill=1)
        centered(label,x,y,'BodyBold',11.2,ink)

    for ident,label,x,y,w,h,_ in RELATIONS:
        c.setFillColor(colors.white)
        c.setStrokeColor(line)
        c.setLineWidth(1)
        p=c.beginPath()
        p.moveTo(x,height-y+h/2)
        p.lineTo(x+w/2,height-y)
        p.lineTo(x,height-y-h/2)
        p.lineTo(x-w/2,height-y)
        p.close()
        c.drawPath(p,stroke=1,fill=1)
        centered(label,x,y,'Body',10.5,ink)

    for ident,label,x,y,rx,ry,_ in ATTRIBUTES:
        c.setFillColor(colors.white)
        c.setStrokeColor(line)
        c.setLineWidth(.9)
        c.ellipse(x-rx,height-y-ry,x+rx,height-y+ry,stroke=1,fill=1)
        centered(label,x,y,'Body',10.5,ink)
        if ident=='matricula':
            span=c.stringWidth(label,'Body',10.5)
            path([(x-span/2,y+6.1),(x+span/2,y+6.1)],ink,.55)

    for _,_,(label,x,y) in LINKS:
        centered(label,x,y,'BodyBold',10,line)
    c.restoreState()
    return {
        'entities': [v[1] for v in ENTITIES],
        'entity_count': len(ENTITIES),
        'relationships': [v[0] for v in RELATIONS],
        'relationship_count': len(RELATIONS),
        'attributes': [v[1] for v in ATTRIBUTES],
        'attribute_count': len(ATTRIBUTES),
        'cardinality_count': len(LINKS),
        'bounds': [35,116,790,499],
        'omitted_detail': 'Acompañamiento, habilidades e historial se explican en el informe y en el modelo lógico.',
    }
