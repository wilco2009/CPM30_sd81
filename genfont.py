#!/usr/bin/env python3
"""Genera font_image.z80 (tabla de fuentes de 256 caracteres, banco 7, $F800).

    python genfont.py

Entradas (en esta misma carpeta):
  FONT.BIN               2048 B = 256 glifos de 8x8. Solo tiene definidos los
                         ASCII imprimibles ($21-$7F), redibujados a 7 pixeles
                         de ancho (la columna derecha queda libre como
                         separacion). El resto de codigos estan en blanco.
  font_atlas_16x16.png   128x128, 1 bit, 16x16 celdas de 8x8 = CP437 completo.
                         Tinta = bit a 1 (colortype 0, o sea 0=negro: la tinta
                         se guarda como 1, hay que leerlo asi y no al reves).

Criterio de mezcla: manda FONT.BIN donde tenga glifo; el atlas rellena todo
lo demas. Como FONT.BIN solo define ASCII imprimible, el resultado es CP437
con el ASCII redibujado -- sin conflicto entre ambos.

Los codigos $80-$FF se guardan COMPLEMENTADOS: el hardware invierte los 8
pixeles cuando el codigo lleva el bit 7 a 1 (video inverso clasico del ZX81,
conservado tambien en modo 256 caracteres -- "if (char_latch_fast[7] &&
!sfSP_en && !sfHR_en) shift_register <= ~v_dout", SD81.v:1559).

Sin dependencias externas: el PNG se decodifica con zlib de la biblioteca
estandar (1 bit, escala de grises, sin entrelazar).
"""

import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))


def load_png_1bit(path):
    d = open(path, 'rb').read()
    assert d[:8] == b'\x89PNG\r\n\x1a\n', 'no es un PNG'
    i, idat, w, h = 8, b'', 0, 0
    while i < len(d):
        ln = struct.unpack('>I', d[i:i + 4])[0]
        typ = d[i + 4:i + 8]
        if typ == b'IHDR':
            w, h, bd, ct, _cm, _fl, il = struct.unpack('>IIBBBBB', d[i + 8:i + 21])
            assert (bd, ct, il) == (1, 0, 0), 'se esperaba 1 bit, gris, sin entrelazar'
        elif typ == b'IDAT':
            idat += d[i + 8:i + 8 + ln]
        i += 12 + ln
    raw = zlib.decompress(idat)
    stride = (w + 7) // 8
    rows, prev, p = [], bytearray(stride), 0
    for _ in range(h):
        ft = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        if ft == 1:
            for x in range(1, stride):
                line[x] = (line[x] + line[x - 1]) & 255
        elif ft == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif ft == 3:
            for x in range(stride):
                a = line[x - 1] if x else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif ft == 4:
            for x in range(stride):
                a = line[x - 1] if x else 0
                c = prev[x - 1] if x else 0
                b = prev[x]
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        elif ft != 0:
            raise ValueError('filtro PNG desconocido: %d' % ft)
        rows.append(line)
        prev = line
    assert (w, h) == (128, 128), 'el atlas debe ser 128x128'
    glyphs = []
    for code in range(256):
        cx, cy = (code & 15) * 8, (code >> 4) * 8
        g = bytearray(8)
        for r in range(8):
            row = rows[cy + r]
            b = 0
            for c in range(8):
                x = cx + c
                if (row[x >> 3] >> (7 - (x & 7))) & 1:      # tinta = bit a 1
                    b |= 0x80 >> c
            g[r] = b
        glyphs.append(bytes(g))
    return glyphs


CP437 = (
    " ☺☻♥♦♣♠•◘○◙♂♀♪♫☼"
    "►◄↕‼¶§▬↨↑↓→←∟↔▲▼"
    " !\"#$%&'()*+,-./0123456789:;<=>?"
    "@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_"
    "`abcdefghijklmnopqrstuvwxyz{|}~⌂"
    "ÇüéâäàåçêëèïîìÄÅ"
    "ÉæÆôöòûùÿÖÜ¢£¥₧ƒ"
    "áíóúñÑªº¿⌐¬½¼¡«»"
    "░▒▓│┤╡╢╖╕╣║╗╝╜╛┐"
    "└┴┬├─┼╞╟╚╔╩╦╠═╬╧"
    "╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀"
    "αßΓπΣσµτΦΘΩδ∞φε∩"
    "≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ "
)

HEADER = """\
; =====================================================================
;  font_image.z80 - tabla de fuentes de 256 caracteres, banco 7
;  ($F800-$FFFF). GENERADO por genfont.py -- no editar a mano.
;
;  Origen de cada glifo:
;    $21-$7F  FONT.BIN   ASCII imprimible, redibujado a 7 pixeles de
;                        ancho (la columna derecha queda libre como
;                        separacion entre caracteres).
;    resto    font_atlas_16x16.png   CP437 completo.
;
;  La posicion de la tabla la fija el registro I (FONT_I=$F8, init.z80)
;  y el modo de 256 caracteres la usa entera, alineada a 2 KB:
;  direccion = {ROMTABLE[15:11], codigo[7:0], linea[2:0]} (SD81.v:1089).
;
;  IMPORTANTE -- los codigos $80-$FF estan guardados INVERTIDOS. El
;  hardware complementa los 8 pixeles cuando el codigo lleva el bit 7 a
;  1 (video inverso clasico del ZX81, conservado tambien en modo 256
;  caracteres: "if (char_latch_fast[7] && !sfSP_en && !sfHR_en)
;  shift_register <= ~v_dout", SD81.v:1559), asi que hay que
;  precomplementarlos para que salgan bien. Por eso esa mitad de la
;  tabla se ve llena de $FF.
;
;  Se ensambla directamente en su sitio: el .cim es plano y se carga
;  desde $6000, asi que el cargador deja la fuente ya puesta y no hace
;  falta copiarla en ?init.
;
;  OJO -- la tabla EMPIEZA en el codigo 32 (FONT_ADDR+$100), no en el 0.
;  Los glifos de los codigos 0-31 no son imprimibles nunca
;  (?co los filtra con "cp 20h / ret c", y la pantalla se borra con el
;  32), asi que ese hueco se reutiliza: los codigos 0-15 para @bnkbf, el
;  buffer de 128 bytes del BIOS bancado (SCB.ASM), los 16-20 para el
;  estado de biosw, los 21-22 para bank$exit y el 23 para las variables
;  de ?xmove/?move (bank.z80) y los 24-31 para lstack, la pila de la
;  BDOS (init.z80). La
;  base de la tabla que ve el hardware es FONT_ADDR: la fija el registro
;  I y el modo de 256 caracteres exige alineacion a 2 KB (SD81.v:1089
;  solo usa ROMTABLE[15:11]).
;
;  CPM3_SD81: la fuente se fue del banco 7 ($F800) al banco de usuario
;  ($D800) -- fase 1 del realineado DRI, ver layout_dri.md. Los 256 bytes
;  de los glifos 0-31 quedan ahora SIN USAR: @bnkbf y las variables que
;  los ocupaban tienen que seguir en memoria comun y se quedan en $F800.
;  El "org" se deriva de FONT_ADDR (init.z80, incluido antes que esto en
;  system.z80) para que no haya que tocar dos sitios.
; =====================================================================

            org  FONT_ADDR+100h

"""

FIRST = 32          # primer codigo con glifo. Los 0-15 los ocupa @bnkbf,
                    # los 16-20 el estado de biosw, los 21-22 bank$exit,
                    # el 23 las variables de ?xmove/?move (bank.z80) y los
                    # 24-31 lstack, la pila de la BDOS (init.z80).
                    # Ninguno es imprimible: ?co filtra todo lo que esta
                    # por debajo de $20, que es justo el codigo 32.


def main():
    binf = open(os.path.join(HERE, 'FONT.BIN'), 'rb').read()
    assert len(binf) == 2048, 'FONT.BIN debe tener 2048 bytes'
    atlas = load_png_1bit(os.path.join(HERE, 'font_atlas_16x16.png'))

    glyphs, src = [], []
    for c in range(256):
        b = binf[c * 8:c * 8 + 8]
        if b != b'\x00' * 8:
            glyphs.append(b); src.append('FONT.BIN')
        else:
            glyphs.append(atlas[c]); src.append('atlas')

    out = [HEADER]
    for c in range(FIRST, 256):
        g = glyphs[c]
        if c >= 0x80:                      # ver la nota de la cabecera
            g = bytes(255 - x for x in g)
        ch = CP437[c]
        name = ch if (ch.isprintable() and ch != ' ') else ('espacio' if ch == ' ' else '?')
        out.append('            defb %s   ; $%02X %s [%s]%s\n' % (
            ','.join('0%02Xh' % b for b in g), c, name, src[c],
            ' INV' if c >= 0x80 else ''))
    out.append('\n')

    path = os.path.join(HERE, 'font_image.z80')
    open(path, 'w', encoding='utf-8').write(''.join(out))
    n = sum(1 for c in range(FIRST, 256) if src[c] == 'FONT.BIN')
    print('%s: %d bytes (codigos %d-255), %d glifos de FONT.BIN, %d del atlas' % (
        os.path.basename(path), (256 - FIRST) * 8, FIRST, n, 256 - FIRST - n))


if __name__ == '__main__':
    main()
