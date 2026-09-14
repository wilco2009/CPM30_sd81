#!/usr/bin/env python3
"""Crea una imagen de disco CP/M vacia para el formato de 2 MB del SD81.

    python mkblank.py [salida.img]        (por defecto BLANK.IMG)

El formato no imita ningun disquete: el "disco" es un fichero en la SD al
que se accede por desplazamiento de bytes (sd_off = (trk*SPT+sect)*128,
diskio.z80), asi que la geometria se elige por conveniencia.

    SPT   128     potencia de dos -> compute_offset son desplazamientos
    BLS  2048     BSH=4, BLM=15
    DSM  1023     1024 bloques de 2K = 2 MB
    DRM   255     256 entradas de directorio = 8 KB = 4 bloques
    AL0   F0h     esos 4 bloques, reservados
    EXM     0     BLS=2048 con DSM>255
    CKS  8000h    medio fijo: sin vector de checksum
    OFF     0     no arrancamos desde estas imagenes

Un disco vacio en CP/M es simplemente el directorio lleno de $E5 (entrada
libre). Se rellena la imagen ENTERA de $E5, que es lo que hacen las
herramientas clasicas y ademas deja claro de un vistazo que no hay datos.
"""

import sys

SPT, SECLEN = 128, 128
BLS, DSM, DRM = 2048, 1023, 255
E5 = 0xE5

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'BLANK.IMG'
    size = (DSM + 1) * BLS
    with open(out, 'wb') as f:
        f.write(bytes([E5]) * size)
    print('%s: %d bytes (%d KB)' % (out, size, size // 1024))
    print('  %d pistas de %d registros de %d B' % (
        size // (SPT * SECLEN), SPT, SECLEN))
    print('  %d bloques de %d B, %d entradas de directorio' % (
        DSM + 1, BLS, DRM + 1))
    print('  libres: %d bytes (%d bloques los ocupa el directorio)' % (
        (DSM + 1 - (DRM + 1) * 32 // BLS) * BLS, (DRM + 1) * 32 // BLS))

if __name__ == '__main__':
    main()
