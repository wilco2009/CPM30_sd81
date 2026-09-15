#!/usr/bin/env python3
"""mkccpimg.py - regenera ccp_image.z80 a partir de CCP3.cim.

Se hacia a mano, y el tamano estaba escrito a pelo en dos equates
(ccp$image$len/ccp$image$padlen). En cuanto la CCP cambia de tamano hay
que rehacer los dos, y olvidarse significa copiar de menos (la CCP se
carga truncada) o de mas. Lo hace este script, llamado desde
build_ccp.bat justo detras de zmac.

El relleno es hasta multiplo de 128 (tamano de @bnkbf) para que el bucle
de copia de ldccp_real nunca lea mas alla de la tabla.
"""
import sys

ORG      = 0xBD00
ALV_BASE = 0xC800          # memmap.inc: lo primero que hay detras
SRC, DST = 'CCP3.cim', 'ccp_image.z80'

data = open(SRC, 'rb').read()
n    = len(data)
pad  = (n + 127) // 128 * 128

if ORG + pad > ALV_BASE:
    sys.exit('[ERROR] la imagen de la CCP (%d B con relleno) desborda '
             '$%04X: $%04X + %d = $%04X' % (pad, ALV_BASE, ORG, pad, ORG + pad))

body = data + bytes(pad - n)
rows = ['            db   ' + ','.join('0%02Xh' % b for b in body[i:i+16])
        for i in range(0, pad, 16)]

hdr = """; =====================================================================
;  ccp_image.z80 - bytes reales de CCP3.cim (org $100 en su ensamblado
;  aislado, build_ccp.bat), incrustados aqui como tabla 'db' porque zmac
;  no tiene 'incbin'. OJO: CCP3.cim NO tiene relleno de ceros desde $0000
;  -- el byte 0 del fichero YA es la direccion $100 (confirmado con xxd:
;  31 1C 0C = LXI SP,$0C1C, la primera instruccion real de start:). La
;  primera version de este fichero asumia relleno de 256 B y cortaba los
;  primeros 256 B REALES de la CCP por error -- confirmado en hardware:
;  "jmp ccp" ($100) ejecutaba una LXI SP corrupta.
;  $BD00: justo detras de RESBDOS.ASM, con margen -- BDOS.ASM empieza en
;  $8900. Viven como DATOS -- MC45/mc45_ext67 solo restringen FETCH de
;  instrucciones (M1), no lecturas normales, asi que no importa que esto
;  pise el bloque 6 ($C000+): nunca se ejecuta aqui, ldccp_real (init.z80,
;  banco 7) lo copia primero a la TPA de usuario ($100). Relleno con ceros
;  hasta multiplo de 128 (tamano de @bnkbf/sector) para que el bucle de
;  copia nunca lea mas alla de esta tabla ({n} B reales, {pad} B con relleno).
;
;  GENERADO POR mkccpimg.py -- no editar a mano.
; =====================================================================

            org  0{org:04X}h

ccp$image$len equ {n}
ccp$image$padlen equ {pad}

ccp$image:
""".format(n=n, pad=pad, org=ORG)

open(DST, 'w', newline='\r\n').write(hdr + '\n'.join(rows) + '\n')
print('[OK] %s: %d B reales, %d con relleno ($%04X-$%04X, margen hasta '
      '$%04X: %d B)' % (DST, n, pad, ORG, ORG + pad - 1, ALV_BASE,
                        ALV_BASE - ORG - pad))
