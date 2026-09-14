#!/usr/bin/env python3
"""Compara el .lst con el .bin y avisa de los bytes que no coinciden.

    python checkimg.py [system]

POR QUE HACE FALTA. En zmac, dos "org" que se solapan NO dan ningun
error: el segundo bloque escribe encima del primero y el listado sigue
mostrando alegremente los dos. Es el fallo que mas veces ha mordido en
este proyecto, y es invisible tanto para el ensamblador como para las
guardas "ds <siguiente>-$" (esas solo cogen los desbordamientos hacia
adelante, no un org clavado a una direccion que se queda corta).

Lo que lo delata es que el .lst dice una cosa y el .cim tiene otra: el
listado refleja lo que el ensamblador CREE que emitio en cada linea, y
el binario tiene lo que gano al final.

Caso real (2026-09-13): "start:" (system.z80) crecio 5 bytes al mover
ahi mc45_ext67, el bucle de unidades de "boot:" se desplazo hasta $605C
y se solapo con "seldsk", que tenia un "org 06058h" literal delante.
El .lst mostraba "6057 C23560  jnz d$init$loop" y el .bin tenia
"C2 79 32", que son los primeros bytes de seldsk. En la maquina, el
bucle saltaba a $3279 y acababa en un HALT.
"""

import os
import re
import sys

BASE = 0x6000            # el .cim es plano y se carga desde aqui
LINE = re.compile(r'^\s*\d+:[^\t]*\t([0-9A-F]{4})  ([0-9A-F]+)\s')


def main():
    stem = sys.argv[1] if len(sys.argv) > 1 else 'system'
    here = os.path.dirname(os.path.abspath(__file__))
    img = open(os.path.join(here, stem + '.bin'), 'rb').read()

    bad = checked = 0
    for ln in open(os.path.join(here, stem + '.lst'),
                   encoding='utf-8', errors='replace'):
        m = LINE.match(ln)
        if not m:
            continue
        addr, hexs = int(m.group(1), 16), m.group(2)
        if len(hexs) % 2:
            continue
        by = bytes.fromhex(hexs)
        if addr < BASE or addr - BASE + len(by) > len(img):
            continue
        checked += 1
        got = img[addr - BASE:addr - BASE + len(by)]
        if got != by:
            bad += 1
            if bad <= 20:
                print('$%04X  lst=%-14s bin=%-14s | %s' % (
                    addr, ' '.join('%02X' % c for c in by),
                    ' '.join('%02X' % c for c in got),
                    ln.split('\t')[-1].rstrip()[:48]))

    print('\n%s: %d lineas comprobadas, %d discrepancias' % (stem, checked, bad))
    if bad:
        print('\nHay org solapados: el binario NO es lo que dice el listado.')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
