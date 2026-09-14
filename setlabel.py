#!/usr/bin/env python3
"""Escribe la etiqueta de directorio de una imagen de disco CP/M 3.

    python setlabel.py C.IMG [NOMBRE] [--no-create] [--no-update]

POR QUE EXISTE. En CP/M 3 el sellado de fecha de los ficheros son DOS
cosas: las ranuras fisicas donde caben los sellos (las crea INITDIR, una
entrada SFCB por cada tres ficheros) y la ETIQUETA DE DISCO, una entrada
de tipo $20 cuyos bits dicen si hay que rellenarlas. Sin etiqueta, la
BDOS ve las ranuras y no escribe nada.

La etiqueta la pone normalmente "SET [CREATE=ON,UPDATE=ON]" -- pero
SET.COM es un .COM con prefijo RSX (lleva dentro el modulo DIRLBL) y
nuestro cargador todavia no entiende ese formato: se encuentra el "C9"
(RET) de $0100 y sale sin hacer nada. Ver memory_map.md.

Esto es el atajo mientras tanto: escribe la entrada a mano desde el
anfitrion. Son 32 bytes.

    byte 0      $20
    1-8         nombre
    9-11        extension
    12          modo:  bit 0 existe
                       bit 4 sello de creacion
                       bit 5 sello de modificacion
                       bit 6 sello de acceso (excluyente con creacion)
                       bit 7 contrasenas
    13-23       sin usar
    24-27       sello de creacion de la etiqueta   (fecha 2B + hora + min)
    28-31       sello de modificacion de la etiqueta

Los bits estan comprobados contra la fuente de la BDOS: "make3a" usa la
mascara 01010000b al crear un fichero, "update$stamp" usa 00100000b y la
apertura usa 01000000b.

OJO: cierra el emulador antes de usarlo. Mientras esta abierto, lo que
CP/M ve y lo que hay en el fichero pueden no coincidir.
"""

import datetime
import sys

SECLEN, ENTRIES = 128, 256
CUM = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]


def cpm_date(d):
    """Dias desde el 1-1-1978, siendo ese dia el 1. Misma cuenta que rtc.z80."""
    n = 365 * (d.year - 1978) + (d.year - 1977) // 4 + CUM[d.month - 1] + d.day
    if (d.year & 3) == 0 and d.month >= 3:
        n += 1
    return n


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = [a for a in sys.argv[1:] if a.startswith('--')]
    if not args:
        print(__doc__)
        return 1
    path = args[0]
    name = (args[1] if len(args) > 1 else 'CPM3').upper()
    nm, _, ex = name.partition('.')

    mode = 0x01
    if '--no-create' not in opts:
        mode |= 0x10
    if '--no-update' not in opts:
        mode |= 0x20

    img = bytearray(open(path, 'rb').read())

    sfcb = sum(1 for i in range(ENTRIES) if img[i * 32] == 0x21)
    if (mode & 0x30) and sfcb == 0:
        print('AVISO: el directorio no tiene SFCB. Pasa INITDIR primero o los')
        print('       sellos no tendran donde escribirse.')

    slot = next((i for i in range(ENTRIES) if img[i * 32] == 0x20), None)
    if slot is None:
        # Ni en una posicion de SFCB (3, 7, 11...): esas estan reservadas.
        slot = next((i for i in range(ENTRIES)
                     if img[i * 32] == 0xE5 and i % 4 != 3), None)
        if slot is None:
            print('ERROR: no hay ninguna entrada libre para la etiqueta.')
            return 1
        accion = 'creada en la entrada %d' % slot
    else:
        accion = 'actualizada en la entrada %d' % slot

    now = datetime.datetime.now()
    d = cpm_date(now.date())
    stamp = bytes([d & 0xFF, d >> 8,
                   int('%02d' % now.hour, 16), int('%02d' % now.minute, 16)])

    e = bytearray(32)
    e[0] = 0x20
    e[1:9] = ('%-8s' % nm[:8]).encode('ascii')
    e[9:12] = ('%-3s' % ex[:3]).encode('ascii')
    e[12] = mode
    e[24:28] = stamp
    e[28:32] = stamp
    img[slot * 32:slot * 32 + 32] = e
    open(path, 'wb').write(img)

    print('%s: etiqueta "%s" %s' % (path, name, accion))
    print('  modo $%02X -> create=%s update=%s access=%s passwd=%s'
          % (mode, bool(mode & 0x10), bool(mode & 0x20),
             bool(mode & 0x40), bool(mode & 0x80)))
    print('  SFCB en el directorio: %d' % sfcb)
    print('  sello: @DATE=%d (%s) %02d:%02d'
          % (d, now.date().isoformat(), now.hour, now.minute))
    return 0


if __name__ == '__main__':
    sys.exit(main())
