# CP/M+ (3.0) SD81Booster — Mapa de memoria banked

Diseño para el modelo banked de CP/M 3, aprovechando los 512 KB de RAM
paginada del SD81Booster. Repo independiente del CP/M 2.2
(`C:\ClaudeCode\CPM_SD81`), que se mantiene intacto como referencia y base
de rutinas de bajo nivel a reutilizar (protocolo MCU, `sddisk.z80`, etc.).

## Terminología (para no confundirse — nos pasó una vez)

- **Banco**: cada uno de los 8 trozos de 8 KB del espacio de
  direccionamiento del Z80 (64 KB), numerados 0–7 (`block[0..7]` en
  `SD81.v`). Es hardware puro, siempre los mismos 8.
- **Página**: cada uno de los 64 trozos de 8 KB de la RAM física de 512 KB.
- **Sistema** / **usuario**: los dos contextos lógicos de CP/M 3 (lo que
  DRI llama "bank 0"/"bank 1" en inglés) — evitamos aquí la palabra
  "banco" para esto, precisamente para no chocar con el significado de
  arriba. "Cambiar a sistema" = reprogramar los bancos 0–6 con las páginas
  del contexto sistema.

## Paginación real de la FPGA (`SD81.v`, confirmado en el fuente)

- El espacio Z80 de 64 KB se divide en **8 bloques de 8 KB** (`block[0..7]`,
  seleccionados por `A15:A13` — decodificación normal de direcciones).
- Cada bloque apunta a una página física de **6 bits (0–63)** →
  **64 páginas × 8 KB = 512 KB** exactos.
- Con `OUT (0E7h),A` "clásico" (half-paging, lo único que usa el CP/M 2.2
  actual) solo se llega a páginas 0–31 (256 KB). Para las 64 páginas
  completas hace falta **`FULL_PAGING` activo** (comando MCU `4`,
  `cfg_reg`) — debe activarse en el arranque de CP/M+, antes de cualquier
  paginación.
- Mecanismo alternativo de programación por puerto, sin depender de
  `block0Writable`: `OUT (C),A` con `C=E7h`, dato de operación en `A`
  (bits 0-3: 9–14), valor real en `B` (que durante el `OUT` aparece en
  `A15:A8` del bus de direcciones). Ya implementado en la FPGA para
  `DFILE_OVR` (9/10/11) y `ATTR_OVR` (12/13/14) — ver más abajo. Útil para
  el modelo banked porque no depende del estado de `block0Writable`, que en
  el 2.2 nos costó una depuración de hardware entera por su fragilidad de
  orden.

## Novedad de hardware: atributos de color por posición (`ATTR_OVR`)

Ya implementado por la sesión de FPGA/interfaz (`ATTR_BASE_OVERRIDE`,
puertos `2059`/`2060`, enable `2061`, mismo patrón que `DFILE_OVR`):
resuelve lo que en el CP/M 2.2 quedó pendiente ("Chroma modo 1 punted to
CP/M+", ver `CPM_SD81/memory_map.md`) — ya no depende de que `DFILE` esté
en los 32 KB bajos, así que es compatible con `DFILE` fuera del TPA.

## Zona común — banco Z80 7, fija, nunca se repagina, **solo datos**

Ocupa siempre la misma página física (7), en los 8 bancos de **cualquier**
contexto (sistema o usuario) — cambiar de contexto solo repagina los
bancos 0–6, nunca el 7. Esto es necesario, no solo cómodo: el refresco de
vídeo de la FPGA lee fuente/pantalla/atributos a través del mismo `block[]`
paginado que usa la CPU (el truco del registro `I` para la fuente pasa por
el mismo mapeo), así que si este banco se repaginase alguna vez el
refresco leería memoria ajena en mitad de un frame. Al no repaginarse
nunca, la tabla de fuentes está siempre accesible durante el refresco y el
rango de pantalla/atributos nunca cambia de RAM física mientras el
hardware la usa.

**Importante — este banco NO puede ejecutar código sin el mod MC45.** El
banco 7 cae en la mitad alta del espacio de direcciones (`A15=1`,
`$8000-$FFFF`), y sin MC45 el Z80 no puede buscar instrucciones (M1) ahí
con garantías — la misma razón por la que el CP/M 2.2 mantiene CCP/BDOS/BIOS
por debajo de `$8000` en modo 32 KB (`MC45=0`). Por eso este banco solo
contiene **datos** (nada que se ejecute como código); el "switcher" de
bancos (`?bank`/`?move`/disco RAM) vive en el banco 3, ver más abajo.

| Elemento | Tamaño aprox. |
|---|---|
| Vars BIOS (+ campos nuevos: contexto activo, estado disco RAM) | ~450 B |
| Tabla de fuentes (256×8) | 2048 B |
| Pantalla — caracteres (80×24 + cabecera, formato igual que 2.2) | 1945 B |
| Pantalla — atributos (Chroma modo 1, mismo formato) | 1945 B |
| Pila | ~600 B |
| **Total** | **~6988 B** de 8192 (margen ~1200 B) |

No lleva `CCPSAVE` (a diferencia del 2.2) — ver más abajo, la copia rápida
de la CCP se guarda en el pool del disco RAM en vez de en común.

## Sistema — 7 páginas (0–6) / 56 KB

CCP + BDOS + BIOS (parte no común). Se selecciona automáticamente durante
las llamadas a BDOS (vía `?bank`) y se restaura el contexto de vuelta al
salir. ~500 B de esto (banco 3, ver "switcher" más abajo) están reservados
para el código de cambio de contexto.

## Usuario — 7 páginas (8–14) / 56 KB

TPA completo, sin más ocupantes — ni CCP ni BDOS ni BIOS viven aquí, por
eso llega a los ~55.5 KB (56 KB menos los ~500 B del switcher duplicado en
el banco 3) frente a los ~41 KB máximos del CP/M 2.2.

**Importante:** el TPA no crece por tener más RAM física disponible — está
limitado por el propio espacio de direcciones de 64 KB del contexto (64 KB
− 8 KB común = 56 KB), tope que ya se alcanza con estas 7 páginas. Las
páginas del disco RAM son físicamente páginas *fuera* de los 8 bancos
direccionables del contexto usuario, así que activar/desactivar el disco
RAM nunca cambia el tamaño del TPA.

## El "switcher" — dos requisitos distintos, no confundir

Todo el código de bajo nivel (`?bank`, `map1blk`, `?xmove`, `?move`, el
driver del disco RAM) comparte el requisito de **no vivir en el banco 7
sin MC45** (es código que se ejecuta, y el banco 7 no soporta eso — ver
arriba). Pero solo **`?bank` (y `map1blk`, la misma primitiva de un solo
`OUT`)** tienen además un segundo requisito, más estricto: **vivir
duplicados**, byte a byte, en la página 3 (sistema) y la página 11
(usuario) del banco 3, mismo offset. `?xmove`/`?move`/el driver del
disco RAM **no** lo necesitan — solo los invoca BDOS (que ya está en
"sistema" al llamar) y siempre restauran el contexto original antes de
su propio `ret`, así que les basta con vivir en zona normal del banco 3
(no duplicada) — ver `move.z80`/`diskio.z80`.

La razón de que `?bank` sí lo necesite: es el único código cuyo propio
`ret` se ejecuta **después** de haber cambiado el banco 3 bajo sus pies
— así es exactamente como lo usa `BIOSKRNL.ASM` (`bnksel: sta @cbnk / jmp
?bank`, un salto de cola: el `ret` final de `?bank` es lo que devuelve el
control al programa de usuario, con el contexto ya en "usuario"). Vive en
`$7E00`–`$7FFF` (últimos 512 B del banco 3, `$6000-$7FFF`, seguro sin
MC45 por estar en `A15=0`), duplicado en la página 3 y la 11 — así, en el
instante en que se decide llamarlo, da igual qué contexto estuviera
activo justo antes. Y como el propio `?bank` reprograma su banco 3 *sobre
sí mismo* como último paso del bucle, la ejecución sigue sin saltos: el
`PC` no cambia, solo cambia lo que hay detrás de esa dirección — y como
el byte que hay ahí es idéntico en ambas páginas, no importa. Ver
`bank.z80` para el fichero real (con `dup_switcher`, la copia de arranque).

**El offset dentro de la página importa.** El switcher está en el
banco 3 en el offset `$7E00-$6000 = $1E00` de la página. Duplicarlo con
una copia por ventana temporal (banco libre + `map1blk`) tiene que escribir
en `ventana_base + $1E00`, no en `ventana_base` — si no, la copia queda en
el offset equivocado de la página y el truco falla en cuanto el banco 3
apunte a la página de usuario.

## Disco RAM — resto, 50 páginas / 400 KB

Montable/desmontable como unidad normal de CP/M (p.ej. `E:`). Acceso vía
"ventana temporal": la rutina de I/O (`ram_read`/`ram_write` en
`diskio.z80` — zona normal del banco 3, no duplicada, porque solo la
invoca BDOS) guarda la página que hay en un banco de TPA del contexto
activo, la
reemplaza por la página del disco RAM que toca, copia los datos, y
restaura la página original antes de devolver el control al programa de
usuario — transparente porque ocurre dentro de una llamada a BDOS, nunca
mientras el programa de usuario está ejecutando. Mismo mecanismo de
`block[]` que el cambio de banco, pero reprogramando un solo bloque en vez
de todos.

### Copia rápida de la CCP (variante elegida, en vez de `CCPSAVE` en común)

En vez de reservar 2 KB en la zona común (como hacía `CCPSAVE` en el 2.2)
o releer la CCP de la SD en cada warm boot, se guarda una copia en **una
página del pool del disco RAM**, traída con la misma técnica de ventana
temporal que el resto del disco RAM — coste cero en común, recarga rápida
en warm boot sin depender de la SD.

## Resumen de páginas físicas (512 KB = 64 páginas de 8 KB)

| Zona | Páginas | Tamaño |
|---|---|---|
| Común (fija, todos los bancos) | 1 | 8 KB |
| Banco 0 (sistema) | 7 | 56 KB |
| Banco 1 (usuario, TPA) | 7 | 56 KB |
| Disco RAM (incluye copia de CCP) | 49 | 392 KB |
| **Total** | **64** | **512 KB** |

---

## Activación de `FULL_PAGING` y coste del cambio de banco

- `FULL_PAGING` se activa con el **comando MCU 29** (no confundir con el
  índice interno `comm_cmd==4` de la FPGA, que es la codificación *dentro*
  del protocolo del comando 29, no el comando en sí). Debe activarse una
  única vez en el arranque de CP/M+, antes de programar ninguna página por
  encima de 31 — sin esto, `OUT (0E7h),A` solo llega a las 32 páginas bajas
  (256 KB, el comportamiento que ya usa el CP/M 2.2).
- Cada `OUT` cambia **un solo bloque** y es inmediato a nivel de FPGA
  (dentro del propio ciclo de la instrucción) — el coste real es el de la
  instrucción Z80 en sí, 11 ciclos. Cambiar los 7 bloques de un banco
  completo (`?bank`) son 7 `OUT` = **77 ciclos** — insignificante frente al
  resto de una llamada a BDOS.
- **Importante — la codificación cambia con `FULL_PAGING` activo.** El
  `OUT (0E7h),A` "clásico" de 8 bits (página en `D7:D3` del propio dato,
  bloque en `D2:D0`) solo alcanza páginas 0-31 y es el que usa el CP/M 2.2.
  Con `FULL_PAGING=1` (obligatorio en CP/M+ para llegar a las 64 páginas),
  la FPGA toma la página de `A13:A8` — es decir, del bus de direcciones
  durante el ciclo de E/S, no del dato — lo que en Z80 solo se consigue con
  la forma de 16 bits `OUT (C),A`: `C=0E7h`, **`B` = página completa (0-63,
  en sus 6 bits bajos)**, `A` = bloque (0-7, en sus 3 bits bajos; el resto
  de `A` no importa). **Todo el código de paginación de CP/M+ —incluido el
  cambio de banco— debe usar esta forma**, no la de 8 bits del 2.2.

```z80
; ejemplo: pagina fisica PAGE en el bloque BLOCK
        ld   b, PAGE
        ld   c, 0E7h
        ld   a, BLOCK
        out  (c), a
```

---

## Asignación de páginas físicas

| Zona | Páginas | Bancos Z80 cubiertos |
|---|---|---|
| Sistema | 0–6 | bancos 0–6 ($0000-$DFFF) del contexto sistema |
| Común (fija) | **7** | banco 7 ($E000-$FFFF), igual en ambos contextos |
| Usuario | 8–14 | bancos 0–6 ($0000-$DFFF) del contexto usuario |
| Disco RAM | 15–63 (49) | fuera del direccionamiento de ambos contextos |

**La zona común usa la página 7 a propósito, no es arbitrario:** es la
página que el bloque 7 trae **por defecto al reset** (mapeo identidad,
`block[7]<=7`), y como `?bank` nunca toca el bloque 7, el arranque no
necesita mapearla explícitamente — ya está correcta desde el encendido.
Encontrado al revisar `banktest.asm`: el vídeo (`DFILE_val`/fuente, en el
bloque 7) nunca se remapea ahí, así que "la página de la zona común" no
podía ser un número elegido a voluntad (como el 14 que había puesto antes)
sin añadir un mapeo explícito de más — tenía que ser la 7. Esto también
obliga a que el banco 1 empiece en la página 8, no en la 7 (si no,
`?bank` con A=1 pisaría la propia zona común al reprogramar el bloque 0).

## `?bank` — selección de contexto (sistema/usuario)

Entra con `A` = contexto a seleccionar (0=sistema, 1=usuario — "bank" en
la terminología de DRI) — lo pone `bnksel` en `BIOSKRNL.ASM`
(`sta @cbnk ! jmp ?bank`) antes de saltar aquí, así que `@cbnk` ya queda
actualizado por BIOSKRNL; `?bank` solo tiene que reprogramar el hardware.
Reprograma los bancos Z80 0–6 con la base física del contexto elegido; el
banco 7 (común) no se toca nunca. **Vive duplicado al final del banco 3
($7E00-$7FFF)** — ver la sección del "switcher" más arriba — no en el
banco común, porque es código y el banco 7 no puede ejecutar código sin
MC45.

```z80
BANK0_BASE  equ 0            ; pagina fisica del bloque 0 del banco 0
BANK1_BASE  equ 8            ; pagina fisica del bloque 0 del banco 1

; ?bank - entra con A = banco a seleccionar (0 o 1). Reprograma los
; bloques 0-6 con base+indice_bloque; el bloque 7 (comun) no se toca.
; D = base del banco, E = bloques restantes, C = indice de bloque actual.
?bank:      push af
            push bc
            push de
            or   a
            jr   nz, bank_is1
            ld   d,BANK0_BASE
            jr   bank_go
bank_is1:   ld   d,BANK1_BASE
bank_go:    ld   e,7
            ld   c,0
bank_loop:  ld   a,d
            add  a,c            ; pagina = base + bloque
            ld   b,a            ; B = pagina (para el OUT)
            push bc             ; guarda B=pagina, C=bloque
            ld   a,c            ; A = bloque (para el OUT)
            ld   c,0E7h
            out  (c),a          ; B=pagina, C=E7h, A=bloque
            pop  bc             ; recupera C=bloque (B se descarta)
            inc  c
            dec  e
            jr   nz, bank_loop
            pop  de
            pop  bc
            pop  af
            ret
```

## `?xmove` / `?move` — copia entre contextos

Contrato derivado directamente de `BDOS30.ASM` (líneas 5551-5568, las dos
llamadas a `deblock12`→`xmovef` antes de una lectura/escritura de disco).
Aquí "banco" es el de DRI (sistema/usuario), no un banco Z80:

- **`?xmove`**: entra con **`B` = contexto destino**, **`C` = contexto
  origen** (para la copia que se hará con la siguiente llamada a `?move`,
  0=sistema, 1=usuario). Solo memoriza los dos valores.
- **`?move`**: entra con `DE` = dirección origen (en el contexto origen
  memorizado), `HL` = dirección destino (en el contexto destino
  memorizado), `BC` = nº de bytes. Como el hardware solo puede tener
  mapeado un contexto a la vez, la copia se hace en trozos de hasta 128
  bytes a través de `@bnkbf` (el buffer de 128 bytes que `BIOSKRNL.ASM`
  declara `extrn` — lo define nuestro módulo): contexto origen → `@bnkbf`
  → contexto destino, repitiendo hasta agotar `BC`, y restaurando `@cbnk`
  al terminar.

**Código vs. datos:** el código de `?xmove`/`?move` en sí va duplicado en
el banco 3 (ver más arriba, es lo único que se ejecuta). `@bnkbf` y las
variables de más abajo son datos puros — no hay problema de MC45 en
leerlos/escribirlos, así que viven en el banco común (7), sin duplicar.

```z80
            public ?bank,?move,?xmove,@bnkbf
            extrn  @cbnk

@bnkbf:     ds   128            ; buffer puente, en zona comun (datos)

xmv$dbnk:   ds   1
xmv$sbnk:   ds   1
mv$de:      ds   2              ; puntero origen, avanza entre trozos
mv$hl:      ds   2              ; puntero destino, avanza entre trozos
mv$cnt:     ds   2              ; bytes restantes
mv$len:     ds   1              ; longitud del trozo actual (1-128)

?xmove:     ld   a,b
            ld   (xmv$dbnk),a
            ld   a,c
            ld   (xmv$sbnk),a
            ret

?move:      ld   (mv$de),de
            ld   (mv$hl),hl
            ld   (mv$cnt),bc

mv$loop:    ld   de,(mv$cnt)
            ld   a,d
            or   e
            jr   z, mv$done      ; restante=0 -> terminado

            ; trozo = min(restante,128) -> A
            ld   a,d
            or   a
            jr   nz, mv$t128     ; D<>0 -> restante>=256 -> trozo=128
            ld   a,e
            cp   129
            jr   nc, mv$t128     ; E>=129 -> trozo=128
            ld   a,e             ; restante<=128 -> trozo=restante
            jr   mv$gotlen
mv$t128:    ld   a,128
mv$gotlen:  ld   (mv$len),a

            ; --- fase 1: banco origen -> @bnkbf ---
            ld   de,(mv$de)
            ld   hl,@bnkbf
            ld   a,(xmv$sbnk)
            call ?bank
            ld   a,(mv$len)
            ld   c,a
            ld   b,0
            ldir                 ; (DE)->(@bnkbf); avanza DE y HL
            ld   (mv$de),de

            ; --- fase 2: @bnkbf -> banco destino ---
            ld   hl,@bnkbf       ; HL=origen del LDIR (@bnkbf)
            ld   de,(mv$hl)      ; DE=destino del LDIR (destino real)
            ld   a,(xmv$dbnk)
            call ?bank
            ld   a,(mv$len)
            ld   c,a
            ld   b,0
            ldir                 ; (HL)=@bnkbf -> (DE)=destino real; avanza DE
            ld   (mv$hl),de      ; guarda el puntero destino avanzado

            ; --- restante -= trozo ---
            ld   hl,(mv$cnt)
            ld   a,(mv$len)
            ld   e,a
            ld   d,0
            or   a
            sbc  hl,de
            ld   (mv$cnt),hl
            jr   mv$loop

mv$done:    ld   a,(@cbnk)       ; deja el hardware como estaba al entrar
            call ?bank
            ld   de,(mv$de)
            ld   hl,(mv$hl)
            ld   bc,0
            ret
```

---

## Disco RAM — driver

### Geometría — 1 pista = 1 página física

En vez de reutilizar la geometría de 26 sectores/pista de los discos SD
(convención heredada de disquete de 8", sin sentido para RAM), el disco RAM
usa **64 sectores lógicos (128 B) por pista = 8192 B = exactamente 1 página
física**. Esto hace que `@trk` sea directamente el índice de página
(0–48) y `@sect*128` el offset dentro de ella — sin multiplicaciones ni
tablas de traducción (`sectrn` con tabla `DE=0`, physical=logical, ya
soportado tal cual por `BIOSKRNL.ASM`).

```
pagina_fisica = RAMDISK_BASE + @trk        ; @trk: 0-48
offset_pagina = @sect * 128                ; @sect: 0-63
```

Tamaño total de bloque de asignación (`BLS`) = 8192 (una pista = un
bloque), `DSM` = 48 (49 bloques, 0–48), bloque 0 reservado para el
directorio → 8192/32 = 256 entradas de directorio (`DRM` = 255). Montable
como unidad `E:` (detalle de `GENCPM`/tabla de unidades, pendiente de la
fase de implementación).

### Transferencia — ventana de un bloque + `@bnkbf`

Las páginas del disco RAM (15–63) no pertenecen a ningún banco (0 ó 1), así
que no se puede usar `?bank` (que solo conoce bancos completos); hace falta
mapear una sola página suelta en un solo bloque. Se elige el **bloque 6**
($C000-$DFFF) del banco en ejecución como ventana temporal — igual de
seguro que lo que ya hace `?move` al sustituir bloques 0-6 enteros
(nada más se ejecuta a mitad de una llamada a BIOS), y se restaura antes de
devolver el control.

```z80
RAMDISK_BASE  equ 15
WINBLK        equ 6              ; bloque usado como ventana (arbitrario)

; map1blk - mapea la pagina A en el bloque E (0-7). No toca @cbnk ni el
; resto de bloques.
map1blk:    push bc
            ld   b,a             ; B = pagina
            ld   c,0E7h
            ld   a,e             ; A = bloque
            out  (c),a
            pop  bc
            ret

rd$winaddr: ds   2                ; direccion Z80 real de la ventana
rd$rdpage:  ds   1                ; pagina fisica del disco RAM (trk+base)
rd$normpage: ds  1                ; pagina "normal" del bloque ventana
                                   ; en el banco actual, para restaurarla

; rdx$setup - calcula rd$winaddr/rd$rdpage/rd$normpage a partir de
; @trk, @sect, @cbnk. No mapea nada todavia.
rdx$setup:  ld   a,(@trk)
            add  a,RAMDISK_BASE
            ld   (rd$rdpage),a

            ld   a,(@sect)
            ld   l,a
            ld   h,0
            add  hl,hl! add hl,hl! add hl,hl! add hl,hl
            add  hl,hl! add hl,hl! add hl,hl        ; HL = @sect*128
            ld   de,WINBLK*2000h                     ; base Z80 del bloque ventana
            add  hl,de
            ld   (rd$winaddr),hl

            ld   a,(@cbnk)
            ld   d,BANK0_BASE
            or   a
            jr   z, rdx$s0
            ld   d,BANK1_BASE
rdx$s0:     ld   a,d
            add  a,WINBLK
            ld   (rd$normpage),a
            ret

; ramdisk_read - copia el sector (@trk,@sect) del disco RAM a (@dma) en
; el banco @dbnk.
ramdisk_read:
            call rdx$setup

            ld   a,(rd$rdpage)! ld e,WINBLK! call map1blk
            ld   hl,(rd$winaddr)! ld de,@bnkbf! ld bc,128! ldir
            ld   a,(rd$normpage)! ld e,WINBLK! call map1blk   ; restaura

            ld   a,(@dbnk)! call ?bank
            ld   hl,@bnkbf! ld de,(@dma)! ld bc,128! ldir
            ld   a,(@cbnk)! call ?bank                        ; restaura
            ret

; ramdisk_write - copia (@dma) en el banco @dbnk al sector (@trk,@sect)
; del disco RAM.
ramdisk_write:
            call rdx$setup

            ld   a,(@dbnk)! call ?bank
            ld   hl,(@dma)! ld de,@bnkbf! ld bc,128! ldir
            ld   a,(@cbnk)! call ?bank                        ; restaura

            ld   a,(rd$rdpage)! ld e,WINBLK! call map1blk
            ld   hl,@bnkbf! ld de,(rd$winaddr)! ld bc,128! ldir
            ld   a,(rd$normpage)! ld e,WINBLK! call map1blk   ; restaura
            ret
```

---

## Primer test en hardware real: `banktest.asm`

Camino más directo para empezar a probar sin esperar a tener
BDOS/CCP/`GENCPM` enlazados: standalone, reutiliza el vídeo ya validado en
`CPM_SD81` y ejercita `FULL_PAGING` + `?bank` + `map1blk` directamente,
imprimiendo `OK`/`FAIL <valor leído>` en pantalla.

**Diseño final:** `?bank`/`map1blk`/`test_bank`/`test_ramdisk` viven
duplicados al final del banco 3 (`$7E00-$7FFF`, ver la sección del
"switcher" más arriba) — el banco 7 no vale para código ejecutable sin
MC45. El arranque/vídeo/impresión sigue en `$6000` (resto del banco 3,
contexto sistema = mapeo identidad = las mismas páginas que carga BASIC).

**Bugs encontrados en la depuración en hardware real** (todos corregidos):

1. **`org` no ascendente rompía el `.cim`.** Una primera versión saltaba
   `$6000→$E000→$7E00`; `zmac` protestaba y, al forzar el build ignorando
   el error, el binario salía mal formado (pantalla completamente negra,
   sin ni siquiera el patrón esperado). Se reordenó a un único `org`
   ascendente (`$6000→$7E00`) y desapareció.
2. **`!` como separador de instrucciones no lo admite este `zmac`** en
   absoluto (9 errores de sintaxis en las líneas que lo usaban, todas las
   del fichero). Se sustituyó por una instrucción por línea. El "Phase
   error" que salía a la vez era efecto colateral de estos errores
   (bytes contados distinto entre pasadas), no una causa aparte.
3. **`REM` con paréntesis sin cerrar rompe `cmd.exe`** en el `.bat` de
   build (`REM ...(test standalone de` sin `)` en la misma línea) — los
   comentarios `REM` no son tan "inertes" como parecen; se quitaron.
4. **Pantalla negra con el programa ejecutándose perfectamente (confirmado
   por traza): la copia de la fuente leía RAM vacía, no la ROM.**
   `copy_font` leía `$1E00` **después** de que las tres primeras
   `OUT (0E7h),A` ya hubieran remapeado el bloque 0 a la página 8 (RAM
   nueva, a ceros) — exactamente el mismo bug, en el mismo orden, que ya
   se había documentado y corregido en `CPM_SD81/boot_cpm_test.asm` días
   antes; no se trasladó la lección a este fichero nuevo. Con la tabla de
   256 caracteres en blanco, todo se dibuja "vacío". Arreglado moviendo
   `copy_font` a **antes** del remapeo de bloques (mientras el bloque 0
   sigue siendo la ROM real) — la lección general: **cualquier lectura de
   `$1E00` debe ir antes de la primera `OUT (0E7h),A`/`map1blk` que toque
   el bloque 0**, en cualquier fichero de arranque nuevo.
5. **Formato del byte de atributo:** es **nibble alto = papel, nibble
   bajo = tinta** (`DOC/superfast_wide_text_modes.md` §5, confirmado por
   el autor del hardware/emulador) — **no** el formato 3+3 bits estilo
   Spectrum (`bits5-3=papel,bits2-0=tinta`) usado por error en una
   primera versión de `clear_attrs`. Con el valor de prueba usado (tinta
   visible, papel 0) ambos formatos coincidían por casualidad, así que
   esto no fue la causa de la pantalla negra — pero es la primera
   sospechosa si un test con más de un color no sale como se espera.

Estado: pendiente de reconstruir con las correcciones y volver a probar
en hardware real.

---

## `BIOSKRNL.ASM` ensambla con `zmac` — sin necesitar `RMAC`

Hito de herramientas: `BIOSKRNL.ASM` (el núcleo invariante del BIOS
banked de DRI, mnemónicos 8080) **ensambla limpio con `zmac -8 --rel`**,
confirmando que podemos evitar montar el toolchain real de DRI
(`RMAC`/`LINK`/`GENCPM`, ejecutables CP/M de 8080) bajo un emulador —
todo se queda en Windows, con la misma herramienta que ya usa el resto
del proyecto.

Pasos dados:
- Copiado `BIOSKRNL.ASM` (fuente de `cpm.z80.de`) a este repo.
- **`!` como separador de instrucciones, no soportado (86 líneas)** —
  mismo problema exacto que ya nos costó con `banktest.asm`. Reescrito
  mecánicamente a una instrucción por línea (ver `build_bioskrnl.bat` /
  el propio `BIOSKRNL.ASM`), preservando la lógica y los comentarios
  tal cual.
- **`modebaud.lib` no venía en ninguno de los tres zips** descargados
  (solo se referencia desde `?devin`, de pasada). Reconstruido desde el
  Apéndice G del *System Guide* (`sysguide.txt`/`.pdf`, guardado en el
  scratchpad de la sesión) — con una corrección real: el símbolo es
  `mb$xonxoff` (confirmado por el propio uso en `BIOSKRNL.ASM`), no
  `mb$xon$xoff` como parecía en el PDF mal extraído.
- Build de prueba: `build_bioskrnl.bat` (`zmac -8 --rel --od . --oo
  rel,lst BIOSKRNL.ASM`) — solo comprueba que ensambla (salida
  relocatable, con `extrn` sin resolver todavía, algo normal y
  esperado a falta de nuestro XIOS).

`BIOSKRNL.ASM` no implementa la lectura/escritura física en sí — `READ`/
`WRITE` sacan la dirección de la rutina real de una tabla por unidad (el
**XDPH**) y saltan ahí con `pchl`. Todo el trabajo real (protocolo MCU,
disco RAM) lo escribimos nosotros.

## Formato del XDPH (fuente: *System Guide* §4.7.3, con la fe de erratas
del propio manual sobre `Media Flag` ya aplicada — el PDF trae un error
ahí, corregido en una fe de erratas al final del libro)

```
XDPH-10   dw   direccion de la rutina WRITE
XDPH-8    dw   direccion de la rutina READ
XDPH-6    dw   direccion de la rutina LOGIN
XDPH-4    dw   direccion de la rutina INIT
XDPH-2    db   UNIT   ; codigo de unidad relativo al driver (va a @rdrv)
XDPH-1    db   TYPE   ; libre para el driver (densidad/tipo de medio)
XDPH+0    dw   XLT    ; tabla de traduccion sector logico->fisico, o 0
XDPH+2..10 db  0,0,0,0,0,0,0,0,0   ; 9 bytes de scratch, los usa el BDOS
XDPH+11   db   MF     ; Media Flag (byte alto de la palabra en XDPH+10)
XDPH+12   dw   DPB    ; puntero al Disk Parameter Block
XDPH+14   dw   CSV    ; puntero al vector de checksum (0 si CKS=8000h)
XDPH+16   dw   ALV    ; puntero al vector de asignacion
XDPH+18   dw   DIRBCB ; 0 si no se usa hashing de directorio (nuestro caso)
XDPH+20   dw   DTABCB ; 0, idem
XDPH+22   dw   HASH   ; 0, idem
XDPH+24   db   HBANK  ; 0, idem
```

`@dtbl` apunta a `XDPH+0` de cada unidad (no al principio de la
estructura) — el prefijo negativo es exactamente lo que `SELDSK`/`READ`/
`WRITE` de `BIOSKRNL.ASM` ya vimos que leen con offsets `-2/-6/-8/-10`.

## DPB — reutilizando el 2.2 (SD) + el diseño nuevo (disco RAM)

Las unidades A-D (SD) reutilizan el DPB ya validado en hardware del 2.2
(`CPM_SD81/bios.z80`), añadiendo los tres campos que CP/M 3 suma sobre
CP/M 2.2 (`OFF`, `PSH`, `PSM` — offset en pistas reservadas para el
sistema, y turno/máscara para cuando el sector físico difiere del
lógico de 128 B; en nuestro caso son iguales, así que `PSH=PSM=0`):

```z80
dpb_sd:     defw 26         ; SPT
            defb 3          ; BSH
            defb 7          ; BLM
            defb 0          ; EXM
            defw 242        ; DSM
            defw 63         ; DRM
            defb 0C0h       ; AL0
            defb 0          ; AL1
            defw 16         ; CKS (medio extraible -- SD si se puede cambiar)
            defw 0          ; OFF (sin pistas reservadas)
            defb 0          ; PSH
            defb 0          ; PSM
```

Disco RAM (geometría ya fijada arriba: 1 pista = 1 página = 64 sectores
de 128 B). Medio no extraíble (RAM, nunca "se cambia el disco"), así que
`CKS=8000h` y `CSV=0` — nos ahorramos el vector de checksum entero:

```z80
dpb_ram:    defw 64         ; SPT
            defb 6          ; BSH  (BLS=8192 = 2^(6+7))
            defb 63         ; BLM
            defb 7          ; EXM  (BLS=8192, DSM<256 -> EXM=7, tabla estandar)
            defw 48         ; DSM  (49 bloques, 0-48)
            defw 255        ; DRM  (256 entradas de directorio)
            defb 80h        ; AL0  (bloque 0 reservado para el directorio)
            defb 0          ; AL1
            defw 8000h      ; CKS  (medio fijo -- sin vector de checksum)
            defw 0          ; OFF
            defb 0          ; PSH
            defb 0          ; PSM
```

## Tabla de unidades (`@dtbl`, 16 palabras) y los 5 XDPH

```z80
            public @dtbl
@dtbl:      defw dph_a,dph_b,dph_c,dph_d,dph_e
            defw 0,0,0,0,0,0,0,0,0,0,0      ; F-P no existen

; --- A-D: SD, comparten dpb_sd; cada una su propio CSV/ALV (2.2) ---
xdph_a:     defw sd_write,sd_read,sd_login,sd_init
            defb 0,0                        ; UNIT=0 (A), TYPE
dph_a:      defw 0                          ; XLT (sin tabla de skew)
            defs 9,0                        ; scratch BDOS
            defb 0                          ; MF
            defw dpb_sd, csv_a, alv_a, 0,0,0
            defb 0                          ; HBANK

xdph_b:     defw sd_write,sd_read,sd_login,sd_init
            defb 1,0                        ; UNIT=1 (B)
dph_b:      defw 0
            defs 9,0
            defb 0
            defw dpb_sd, csv_b, alv_b, 0,0,0
            defb 0

xdph_c:     defw sd_write,sd_read,sd_login,sd_init
            defb 2,0                        ; UNIT=2 (C)
dph_c:      defw 0
            defs 9,0
            defb 0
            defw dpb_sd, csv_c, alv_c, 0,0,0
            defb 0

xdph_d:     defw sd_write,sd_read,sd_login,sd_init
            defb 3,0                        ; UNIT=3 (D)
dph_d:      defw 0
            defs 9,0
            defb 0
            defw dpb_sd, csv_d, alv_d, 0,0,0
            defb 0

; --- E: disco RAM, sin CSV (medio fijo) ---
xdph_e:     defw ram_write,ram_read,ram_login,ram_init
            defb 0,0                        ; UNIT=0 (unico, propio driver)
dph_e:      defw 0
            defs 9,0
            defb 0
            defw dpb_ram, 0, alv_e, 0,0,0
            defb 0
```

`sd_read`/`sd_write`/`sd_login`/`sd_init` y `ram_read`/`ram_write`/
`ram_login`/`ram_init` son referencias hacia adelante (`extrn` o
etiquetas locales, según en qué módulo acaben) — se escriben en el
siguiente paso (adaptar `sddisk.z80` y el driver del disco RAM al
contrato `READ`/`WRITE`/`LOGIN`/`INIT` de la tabla 4-11 del *System
Guide*: entran con `DE`=puntero al XDPH, parámetros en `@adrv`/`@rdrv`/
`@trk`/`@sect`/`@dma`/`@dbnk`, devuelven código de error en `A`).

**Escrito**: `diskio.z80` (`sd_read`/`sd_write`/`sd_login`/`sd_init` +
`ram_read`/`ram_write`/`ram_login`/`ram_init`, contrato de la tabla 4-11
completo, más `csv_a`-`csv_d`/`alv_a`-`alv_e`) y `sddisk.z80` (protocolo
MCU, copiado del 2.2 sin cambios salvo quitar `compute_offset`/
`diskname_a-d`, que ahora viven en `diskio.z80` usando `@trk`/`@sect` de
`BIOSKRNL` en vez de las variables propias del 2.2). Novedad respecto al
2.2: tanto `sd_read`/`sd_write` como `ram_read`/`ram_write` pasan siempre
por `@bnkbf` (128 B, coincide con el tamaño de sector) para llegar a
`(@dma)` en el banco `@dbnk` — necesario porque el llamador puede estar
en un banco distinto al que ve el driver; escribir directamente en
`(@dma)` sin este paso fallaría en cuanto `@dbnk <> @cbnk`.

`csv_a`-`csv_d` (16 B cada uno, `(DRM/4)+1`) y `alv_a`-`alv_e` (63 B
para A-D, 14 B para `E:`, `(DSM/4)+2` — **doble bit por bloque,
obligatorio en CP/M 3 banked**, a diferencia del único bit que usaba el
2.2 en `alv0`-`alv3`, 31 B, que no sirven tal cual aquí). `E:` no lleva
`CSV` — medio fijo (`CKS=8000h` en `dpb_ram`), nos ahorramos ese buffer.

También materializado el módulo del "switcher" como ficheros reales:
`bank.z80` (`?bank`/`map1blk`, duplicados) y `move.z80` (`?xmove`/
`?move`/`@bnkbf`, zona normal) — ver la sección de más arriba.

**Escrito**: `drvtbl.z80` (`@dtbl` + los 5 XDPH + `dpb_sd`/`dpb_ram`,
verificado a mano el conteo de bytes de cada XDPH contra los offsets del
*System Guide*) y `chario.z80` (`?ci`/`?co`/`?cist`/`?cost`/`?cinit` +
`@ctbl`, terminal ADM-3A + teclado ZX81 + cursor parpadeante, copiado del
2.2 sin cambios de lógica — solo renombrar `_const`/`_conin`/`_conout` a
`?cist`/`?ci`/`?co` y añadir `?cost`/`?cinit`, triviales al no haber
dispositivo serie real. `@ctbl` usa por fin `modebaud.lib` para algo real,
no solo la referencia de paso de `?devin`).

## `BIOSKRNL.ASM` asume "común = memoria alta = siempre ejecutable" — no vale aquí

Hallazgo real durante la integración: `BIOSKRNL.ASM` empieza con
`cseg ; GENCPM puts CSEG stuff in common memory` — DRI da por hecho que
**toda** la tabla de saltos del BIOS (`?boot`/`?wboot`/`?const`/.../`?xmov`)
vive en zona común, alcanzable desde cualquier banco. En hardware normal
(común = memoria alta, siempre ejecutable) esto no es un problema; en el
nuestro (sin MC45, banco 7 no ejecuta código) sí — y no es solo cosa de
`?bank` esta vez: programas de usuario reales (WordStar, Turbo Pascal...)
llaman a estas entradas **directamente**, sin pasar por BDOS, para ganar
velocidad de consola — con "usuario" ya activo.

**Solución** (confirmada con el usuario): la tabla de saltos se movió de
`BIOSKRNL.ASM` a `bank.z80` (zona duplicada, junto a `?bank`/`map1blk`).
Cada entrada pasa de `jmp rutina` a `xor a / call bnksel / jmp rutina` —
`bnksel` (no `?bank` a secas) porque también actualiza `@cbnk`, necesario
para que `?move` no se desincronice después. `?boot` es la única
excepción: se ejecuta una sola vez al arrancar, antes de `FULL_PAGING`,
así que forzar un cambio de contexto ahí sería prematuro. Los *cuerpos*
reales (`boot`/`wboot`/`const`/...) se quedan intactos en `BIOSKRNL.ASM`,
solo se les añadió `public` (antes eran internos) para que `bank.z80`
pueda llegar a ellos con `extrn`. `?time` (pendiente de RTC real) se
quedó como no-op en `move.z80`.

**Pendiente de verificar**: si `public`/`extrn` se comportan igual en un
ensamblado combinado (todo por `include`, absoluto) que en las pruebas
`--rel` aisladas que hemos hecho hasta ahora — no se ha probado todavía
un ensamblado conjunto de verdad.

Pendiente: el tamaño exacto de la zona común una vez se sepa cuánto
ocupa todo esto en el banco 7, y un fichero de arranque real que junte
todo (`bank.z80`+`move.z80`+`diskio.z80`+`drvtbl.z80`+`chario.z80`+
`BIOSKRNL.ASM`) para poder ensamblarlo de una pieza.

**`?time` (RTC real) — pendiente, no olvidar.** Ahora mismo es un no-op
en `move.z80`. El firmware del MCU ya tiene `RTC.cpp`
(`SD81-Booster/Arduino/SD81BoosterV2_*_STM32`) — falta conectarlo aquí
con el protocolo MCU (estilo `mcu_send`/`mcu_recv`, como `sddisk.z80`) y
el contrato de `?time` del *System Guide* §4.6. También anotado en
memoria persistente para que no se pierda entre sesiones.

## MC45 obligatorio, permanentemente — decisión consciente, no provisional

Confirmado en hardware real (primera prueba de arranque conjunto): CP/M+
**requiere MC45 activo desde el primerísimo instante** (`start:` en
`system.z80`, comando MCU `0x13`, antes incluso de `jp ?boot`) y no hay
forma de evitarlo mientras el modelo banked exista.

Motivo de fondo, no solo el vídeo: el modelo banked de CP/M 3 exige una
zona "común" de verdad — código/datos que sobrevivan a un cambio de
banco sin duplicarse (`boot$1`...`bnksel`+`xofflist`+`boot$stack`,
`@cbnk`; ver más abajo). En este hardware esa zona común solo puede
*ejecutar* código gracias a MC45 (engaña al generador de NOPs nativo del
ZX81 para permitir fetch de instrucciones con A15=1). Sin MC45, banco 7
sigue siendo un área de memoria fija, pero inutilizable como "común
ejecutable" — y sin común ejecutable no hay banked BIOS que funcione.
Se evaluó (con el usuario) la alternativa de evitar MC45 — el propio
`SD81.v` explica por qué: fuerza `/HALT=0` mientras `/M1=0` (fetch en
la mitad alta de memoria), lo cual estresa la señal más de lo normal —
pero la única forma real de evitarlo sería limitar CP/M+ a 32 KB de
espacio de direcciones útil, lo que lo dejaría prácticamente inútil (y
para eso ya está el CP/M 2.2, que si funciona sin MC45). Decisión:
aceptar el estrés de hardware, MC45 fijo todo el rato. Además, todo el
código movido a banco 7 vive en la mitad `A14=1` (`$C000-$FFFF`), así
que también hace falta `sfast_mode_en` activo (POKE 2045,174 en
`?init`) — no supone ninguna restricción extra real porque ya usamos
Superfast para todo el vídeo (nadie usa el salto nativo a `DFILE+$8000`
que el generador de NOPs protegía).

## Bug real encontrado y corregido: `boot$1`/`set$jumps`/`@cbnk` en banco 3 en vez de banco 7

`set$jumps` (dentro del `cseg` de `BIOSKRNL.ASM`) cambia de contexto A
MITAD de su propia ejecución (`mvi a,1 / call ?bnksl`, para dejar
"usuario" seleccionado antes de cargar la CCP en su TPA) y luego SIGUE
ejecutando más código (escribir los vectores de página cero). Si ese
código — y la pila que usa, `boot$stack` — vive en banco 3 normal (no
duplicado, a diferencia de la tabla de saltos / `?bank` / `map1blk`),
en cuanto el banco cambia bajo sus pies la CPU pasa a buscar
instrucciones (y a hacer `pop` del `ret`) en la página de usuario, que
nunca tiene ese código cargado → ejecución de basura. Confirmado en
hardware con el depurador: el `ret` de `set$jumps`, justo después del
cambio de banco, hacía `pop` de basura y el PC se iba a `$FFFF`.

Mismo problema, más sutil, en `@cbnk`: `bnksel` hace `sta @cbnk` ANTES
de que `?bank` cambie de banco, así que escribe en la copia de la
página que se está ABANDONANDO, no en la de destino — una lectura
posterior desde el otro contexto leería basura/desactualizado.

**Solución real** (no duplicación, sino lo que el `cseg` de DRI pedía
desde el principio): mover `boot$1`...`bnksel`+`xofflist`+`boot$stack`
a `$F200` (banco 7, hueco libre entre `DFILE_val` y `FONT_ADDR`) y
`@cbnk` a `$E064` (justo detrás de las variables del SCB), con `org`
explícitos en `BIOSKRNL.ASM` (ver comentarios ahí) y volviendo a
`$6058` después para que `seldsk` y todo lo de detrás mantenga las
mismas direcciones que antes. En banco 7, `?bank` nunca toca nada, así
que el problema desaparece por construcción.

**Primer hito de arranque alcanzado** (objetivo de la sesión): con esto,
el mensaje completo `INITNOCCP` se ve en hardware real — `?boot` →
`boot:` → `?init` (vídeo + MC45 + `FULL_PAGING` + duplicar switcher) →
bucles `?cinit`/INIT de disco → `boot$1` → `set$jumps` (cambio a
"usuario" limpio) → `?ldccp` (stub) → mensaje "NOCCP" + parada. Falta
CCP3.ASM/BDOS3 reales para sustituir el stub.

## CCP3.ASM: ensambla limpio, simplificada (sin LOADER3.ASM/RSX)

`CCP3.ASM` (fuente real de DRI, `cpm3src.zip`) ensambla limpio con
`zmac` en aislado (`build_ccp.bat`). Cambios respecto al original:
`ccporg` de `$040A` a `$100` (sin loader no hace falta reservarle
hueco), `multi equ false` (líneas de comando múltiple, mecanismo RSX),
y el bloque de detección/reubicación del loader en `start:` eliminado
por completo (se ejecutaba siempre, no solo con `multi`, y sin
`LOADER3.ASM` no hay nada que detectar). `scbaddr`/`banked` reubicadas
de direcciones fijas del loader (que ahora caerían dentro de la propia
CCP) a variables reales junto a `realdos`. 3 erratas de transcripción
corregidas (`chain$env`→`chainenv`, `chain$flg`→`chainflg`,
`set$byte`→`setbyte`).

**Nota real**: la CCP por sí sola no hace nada — su primera instrucción
en `start:` ya es `call bdos`. No se puede probar de verdad sin la BDOS
integrada.

## BDOS.ASM: ensambla limpio (falta enlazar con nuestras direcciones reales)

Receta real de la BDOS *banked*, encontrada en el `MAKEFILE` del propio
`cpm3src.zip` (NO es solo `BDOS30.ASM`): concatenación de
**`CPMBDOS2.ASM` + `CONBDOS.ASM` + `BDOS30.ASM`**, en ese orden
(`CPMBDOS2.ASM` trae `BANKED equ on`/`MPM equ off`, que activa las
secciones `if BANKED` del resto). `makedate.lib` (macros triviales de
fecha/copyright) es la única dependencia externa.

Bugs encontrados y corregidos para que ensamble:
- **`zmac` no evalúa bien `if not BANKED`/`if not MPM`** (o alguna
  combinación con `not`) en esta fuente — confirmado con un análisis
  propio de la anidación de 246 bloques `if`/`else`/`endif`: bloques
  que debían quedar inactivos se incluían (`Mult. def.`) y bloques que
  debían activarse se omitían (`Undeclared`). Solución: resolver los
  246 condicionales nosotros mismos en preprocesado (script, con
  `BANKED=1`/`MPM=0` fijos) y dejar solo el código de la rama activa,
  quitando `if`/`else`/`endif` del todo — más fiable que depender de
  cómo los interprete `zmac` para esta fuente en concreto.
- **~40 erratas de transcripción tipo "$ de más o de menos"**, en
  ambos sentidos, entre la definición real de una etiqueta y sus
  llamadas (`mult$cnt`↔`multcnt`, `gets1`↔`get$s1`,
  `setenddir`↔`set$end$dir`, etc.) — corregidas con alias `equ`, sin
  tocar el código disperso por las ~9000 líneas. Una (`dirbios4`,
  función 50 "Direct BIOS call", poco usada) no tiene definición real
  en la fuente en absoluto — alias a `dir$bios2` por lógica del salto,
  sin verificar en hardware.
- Binarios con `$` como separador de nibbles (`0001$1111b`, sintaxis
  RMAC que `zmac` no soporta) — `$` quitado mecánicamente.

**Pendiente antes de integrar en `system.z80`** (ver discusión con el
usuario, decisión tomada): `bios$pg`/`scb$pg`/`resbdos$pg`/`bnkbdos$pg`
en `BDOS.ASM` (y en `RESBDOS.ASM`, aún sin integrar) están definidos
como offsets relativos a `base` (`base+$FB00` etc.) siguiendo el layout
de DRI para CP/M 3 *no-banked* (BIOS+SCB+BDOS apretados justo antes de
`base`, todo en una zona siempre alcanzable). Ese layout no encaja con
el nuestro (tabla de saltos duplicada en banco 3, SCB en banco 7) ni
tiene sentido para banked (el jump table duplicado solo puede ocupar
512 B, la BDOS no cabe ahí). Decisión: NO reorganizar nuestro layout ya
validado en hardware — en su lugar, sustituir esos equates de offset
por alias directos a nuestras etiquetas reales (`bootf equ ?boot`,
`scb$pg equ 0E000h`, etc.). Esto no afecta a la compatibilidad con
software CP/M real: ningún programa de usuario ve `bios$pg`/`scb$pg`
directamente, es cableado interno BIOS↔BDOS↔SCB.

**`RESBDOS.ASM`** (`cpm3src.zip`): módulo residente banked, se
ensambla y enlaza APARTE del anterior (`resbdos3.spr`, no forma parte
de `bnkbdos3.spr`) — trae `gets1`(`get$s1`)/`rd$dir`/`getxfcb1`/
`seek$dir`/hash de directorio/etc., las rutinas que `BDOS.ASM` invoca
vía `resbdos$pg+N`. Aún sin integrar (siguiente paso).
