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
bancos 0–6, nunca el 7.

**Corrección (2026-09-12) sobre por qué la pantalla tiene que vivir aquí.**
Antes se decía en este documento que el refresco de la FPGA lee
fuente/pantalla/atributos a través del mismo `block[]` paginado que usa la
CPU. **Es falso**, comprobado en el Verilog: la FPGA lee de una *shadow
RAM interna* (`SD81.v:844-858`) que captura **todas** las escrituras del
Z80 indexadas por **dirección lógica** (`shadowram_we` = cualquier
escritura a memoria, `shadowram_addr = Addr[15:0]`), sin pasar por el
paginado ni saber nada de él. El motivo real por el que pantalla y
atributos tienen que estar en `$E000-$FFFF` es el complementario: como la
shadow captura escrituras de *cualquiera*, el buffer tiene que vivir en un
rango lógico donde ningún programa de usuario vaya a escribir nunca — y el
único que cumple eso es el que queda por encima del TPA, o sea el banco 7.
La tabla de fuentes sí depende del registro `I` (`ROMTABLE`), y en modo 256
caracteres ocupa 2 KB alineados a 2 KB, lo que la ata a `$F800` aquí.

**Consecuencia práctica:** ni `DFILE` ni `ATTR` necesitan alineación
alguna. Con el override activo la FPGA calcula
`char_addr_80 = DFILE_eff+1+fila+col` y
`attr_addr_m1 = ATTR_BASE_OVERRIDE+1+...` con sumadores de 16 bits
completos (`SD81.v:1048/1070`; el comentario del propio Verilog lo dice:
*"base COMPLETAMENTE independiente, dirección de 16 bits sin truncar ni
forzar el bit 15"*). Estaban en `$E200`/`$EA00` por costumbre, no por
obligación — ver la sección del reempaquetado más abajo.

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
vía `resbdos$pg+N`.

## BDOS.ASM + RESBDOS.ASM: ensamblan limpios juntos (`bdos_full.z80`)

Al integrar `RESBDOS.ASM` se descubrió que, pese a enlazarse aparte en
el `GENCPM` real, SÍ hace falta compartir ámbito de ensamblado con
`BDOS.ASM` en nuestro enfoque plano (usa `fx`/`dcnt`/`hash`/`bootf`
etc. sin declararlos — la fuente original tampoco los declara con
`extrn`, se apoya en que RMAC resuelve símbolos no definidos como
externos al enlazar). Bugs encontrados y corregidos:

- **`scb$pg`/`bios$pg`-relativos → alias directos.** `bios$pg+N`
  (`bootf`..`xmovef`) ahora son alias a nuestra tabla de saltos real
  (`?boot`..`?xmov`, `bank.z80`). `scb$pg` ahora vale `$E000` (la misma
  base que `SCB.ASM`, confirmado que los rangos de offset no se
  solapan — las dos mitades de la misma estructura real). Sin
  necesidad de reservar almacenamiento explícito para los campos del
  SCB: son solo direcciones hacia RAM real del banco 7, siempre
  mapeada (igual que `@CIVEC` etc. en `SCB.ASM`).
- **Bloque `resbdos$pg`-relativo eliminado de `BDOS.ASM`** — con
  `RESBDOS.ASM` en el mismo ámbito, sus etiquetas reales
  (`hashmx`/`make$xfcb`/`kbchar`/etc.) sirven directamente.
- **Choques de nombre entre `BDOS.ASM` y `RESBDOS.ASM`** (dos módulos
  que en DRI se enlazaban aparte, con sus propios ámbitos —
  perfectamente normal ahí, pero un choque real al compartir uno
  solo): `RESBDOS.ASM` tenía su propia copia de `SCB:`, `olog`/`rlog`
  (redundante, eliminada — ver punto anterior) y sus propias rutinas
  internas (`functab`/`func3`/`func6`-`func10`/`sta$ret`/`goback`/
  `compare`/`subdh`/`hash$tbla`/`search$hash`(la de bajo nivel, DISTINTA
  del envoltorio de alto nivel del mismo nombre en `BDOS.ASM`)/`aret`/
  `entsp`/`serial`) que casualmente coinciden con nombres que
  `BDOS.ASM` usa para OTRA cosa — renombradas con prefijo `rb$` en
  `RESBDOS.ASM`. Un caso eran mayúsculas vs minúsculas (`CONSTX` en
  `BDOS.ASM` vs `constx` en `RESBDOS.ASM` — `zmac` no distingue caso,
  choca igual) — mismo tratamiento.
- **Un `equ` como referencia hacia delante desestabiliza el ensamblado
  en varias pasadas.** El bloque de ~40 alias por erratas de
  transcripción estaba justo detrás de `maclib makedate`, muy al
  principio del fichero — casi todos apuntaban a etiquetas definidas
  miles de bytes más abajo. Eso causaba `Phase error` en sitios sin
  relación aparente (`bdose2`, a solo 25 líneas de "arriba") y
  `Mult. def.` fantasma en `RESBDOS.ASM`. Solución: mover el bloque
  entero al final del fichero (referencia hacia atrás pura) — el orden
  de un `equ` no cambia lo que significa, solo cuándo se resuelve.
  `xdmaad`/`srch$hash` (apuntan a `RESBDOS.ASM`, que va *después* de
  `BDOS.ASM`) tuvieron que ir aún más lejos: en `bdos_full.z80`,
  después de incluir los dos ficheros.

## BDOS integrada en `system.z80` — `org $8800`, no `$0000`

Se probó primero `org 0000h` (banco 0-2, `$0000-$5FFF` libres, de sobra
para los ~13 KB de `BDOS.ASM`+`RESBDOS.ASM`) — ensambla bien, pero
**arranque muerto en hardware real, ni siquiera "INIT"**. Motivo: el
procedimiento de carga (`LOAD FAST SYSTEM.BIN CODE 24576`) mete el
`.cim` como un bloque plano único a partir de `$6000` — con `org 0000h`
el `.cim` pasa a empezar en `$0000`, así que al cargarlo en `$6000` se
desplaza TODO el fichero `$6000` bytes de más (`start:` deja de estar
donde `RAND USR 24576` espera). La BDOS tiene que quedar CONTIGUA con
el resto del XIOS, no en una zona libre cualquiera del mapa de páginas
— nuestro método de carga no admite bloques separados.

Solución: `org $8800` (justo detrás de `init.z80`, que termina en
`$87FE`) — sigue en los bloques 4-5, sin necesitar `mc45_ext67`, y cabe
de sobra (~13 KB, hasta ~`$BC00`).

**Pendiente**: integrar `CCP3.ASM` (mismo problema de contigüidad a
tener en cuenta) y resolver cómo `?ldccp` carga la CCP real desde
disco.

### Bug real de DRI encontrado al mover `base` de $0 a $8800

`BDOS30.ASM` (línea 6231 de la fuente original, sin tocar) tiene:
```
last:
	org	(((last-base)+255) and 0ff00h) - 1
	db	0
```
Calcula bien un *tamaño* relativo a `base` (para redondear al siguiente
límite de página) pero lo usa directamente como dirección **absoluta**
de destino del `org`, sin volver a sumar `base`. Invisible mientras
`base=$0000` (sumar 0 no cambia nada) — confirmado en hardware que
rompía todo lo que va detrás (`RESBDOS.ASM` aterrizaba en `$2E00` en
vez de justo detrás de `BDOS.ASM`, ~`$B600`) en cuanto `base` pasó a
ser `$8800`. Corregido en nuestra copia (`base + (...)`). Hay una
segunda ocurrencia idéntica en la fuente original (línea 6240, con
`-192` en vez de `-1`) que no llegó a nuestro `BDOS.ASM` — cae en una
rama `if`/`else` que el preprocesado de condicionales dejó inactiva.

## CCP corriendo de verdad: hito alcanzado, pero con un bug de fondo pendiente

Sesión larga de depuración paso a paso (trazado con el debugger,
puntos de control, breakpoints de escritura en el puerto `$E7`) que
llevó `system.z80` desde "INITNOCCP" hasta la CCP real ejecutándose y
llegando a la BDOS — con bugs reales encontrados y corregidos por el
camino. Quedan documentados aquí en orden, porque cada uno solo se hizo
visible al arreglar el anterior.

### `ccp_image.z80`: el `.cim` de `CCP3.ASM` NO tiene relleno desde `$0000`

Al incrustar los bytes de `CCP3.cim` (org `$100`) como tabla `db`, la
primera versión asumía 256 B de relleno de ceros al principio (como
`system.cim`, que sí empieza en `$6000` con todo lo de detrás relleno)
y recortaba `data[0x100:]`. Comprobado con `xxd`: **`CCP3.cim` no tiene
ese relleno** — el byte 0 del fichero YA es la dirección `$100`
(`31 1C 0C` = `LXI SP,$0C1C`, la instrucción real de `start:`). El
recorte quitaba los primeros 256 B REALES de la CCP. Confirmado en
hardware: `"jmp ccp"` ejecutaba una `LXI SP` corrupta. Corregido usando
el fichero completo sin recortar.

### `?bank`: dos bugs de pila reales, no uno

1. **El propio bucle de `?bank` usaba la pila del llamante.** `push
   bc`/`pop bc` (para guardar página+bloque mientras `C` se reutiliza
   para el puerto `$E7`) caía en la pila de quien llamó a `?bank` — que
   puede estar en CUALQUIERA de los bloques 0-6 que el propio bucle
   está reprogramando (p.ej. la pila de la CCP, en su TPA, bloque 0).
   En cuanto el bucle reprograma ESE bloque, el contenido de la pila
   cambia de página física bajo sus pies. Arreglado: `?bank` usa ahora
   su propia pila temporal (`bank$stack`, banco 7, `$F600`) mientras
   dura el bucle.

2. **Más sutil — la propia dirección de retorno del llamante, no solo
   los `push`/`pop` internos.** Aunque `?bank` ya no escribe en la pila
   del llamante, la dirección de retorno que el llamante dejó ahí (con
   su `call bnksel`/`call ?bank`, ANTES de que `?bank` se ejecute)
   también vive en uno de esos bloques 0-6 — y un `ret` normal al final
   la lee DESPUÉS de que el bucle haya reprogramado ese bloque, sacando
   basura. Arreglado: `?bank` hace `pop hl` como PRIMERA instrucción
   (lee la dirección de retorno mientras la página buena todavía está
   mapeada), la guarda en `bank$retaddr` (banco 7), y al final hace
   `ld hl,(bank$retaddr) / jp (hl)` en vez de `ret` — sin depender de
   una pila que puede haber cambiado de página física entre medias.

   **IMPORTANTE**: `bank$retaddr`/`bank$savesp` son variables ÚNICAS
   (no una pila de ellas) — si `?bank` se llega a invocar de forma
   verdaderamente reentrante (una llamada a `?bank` ocurre mientras
   otra todavía no ha terminado de "salir"), la segunda pisaría los
   datos de la primera. No debería pasar con el diseño actual (cada
   llamada entra y sale limpiamente antes de que nada más pueda volver
   a llamar a `?bank`), pero si aparecen síntomas parecidos a los de
   abajo en un sitio nuevo, revisar esto primero.

Con estos dos arreglos, `call5_entry` → `bnksel` → `?bank` → `bdos:`
(RESBDOS.ASM) ya funciona: se confirmó en hardware que `bdos:` activa
`lstack` correctamente (`SP=$F497`) y el primer nivel de despacho
funciona.

### PENDIENTE (para retomar mañana) — `entsp`/`goback`/`retmon`: restaurar `SP` bajo el contexto equivocado

Symptom confirmado en hardware con trazado paso a paso: tras bastante
procesamiento real de la BDOS (dispatch, `bank$bdos`, `?move`, copias
de buffer...), la ejecución acaba desviándose a la tabla de fuentes
(banco 7, `$FDxx`-`$FExx`) ejecutada como si fuera código, y de ahí a
una zona de la propia CCP con contenido que no es código real —
eventualmente un `RST 38` cae en el gestor de errores de la ROM del
ZX81 (con interrupciones REACTIVADAS, algo que nosotros nunca hacemos
-- confirma que en ese punto ya no estamos ejecutando nada nuestro).

**Mecanismo identificado** (no arreglado todavía): tanto `BDOS.ASM`
(`goback`/`retmon`, con la variable `entsp`) como `RESBDOS.ASM`
(`rb$goback`, con `rb$entsp`) usan el patrón:
```
; al ENTRAR en la funcion (con un contexto X activo):
dad sp
shld entsp          ; guarda el SP actual (numero, no lo que hay debajo)
lxi sp,lstack       ; cambia a pila propia para procesar
...
; al SALIR (much mas tarde):
lhld entsp
sphl                ; restaura ESE MISMO NUMERO como SP
...
ret                 ; y vuelve usando esa pila "restaurada"
```
Esto es exactamente correcto SI el contexto (sistema/usuario) sigue
siendo el mismo en el momento de restaurar que en el momento de
guardar. En nuestro sistema banked NO tiene por qué serlo: en concreto,
`bank$bdos` (RESBDOS.ASM) cambia a "usuario" el ÉL MISMO, con un salto
de cola (`mvi a,1 / jmp selmemf`, no un `call`+`ret`), ANTES de que el
control vuelva al punto desde donde se guardó `entsp`. El número
guardado en `entsp` (p.ej. `$0C18`) es la dirección REAL de la pila de
la CCP en usuario -- pero si en el momento en que `goback`/`retmon` lo
restauran el contexto activo NO es el mismo que cuando se guardó (por
ejemplo, seguimos en "sistema" porque el cambio de `bank$bdos` fue mas
alla en la cadena de llamadas de lo esperado, o al reves), esa misma
direccion numerica apunta a una pagina fisica distinta -- y lo que se
lee ahi (para el `ret` final) es basura.

Confirmado en la traza real: `?bank` (con el arreglo de `pop hl` ya
puesto) hace su propio `pop hl` nada mas entrar y saca `$FD12` --
significa que ese valor YA estaba mal puesto en la pila (en `$0C1A`,
dentro del rango de `rb$entsp`) ANTES de que `?bank` se ejecutara --
justo la vuelta de `rb$goback` que precede a esa llamada.

**Para retomar mañana**: hace falta trazar con cuidado, para la
secuencia real de esta sesión (función 49, `scbf`), en qué momento
exacto cambia el contexto sistema/usuario respecto a cuándo se
guarda/restaura cada `entsp` -- lo más probable es que la solución
pase por:
- Anadir contabilidad explicita del contexto (que `entsp`/`rb$entsp`
  vayan acompañados de "en qué contexto se guardó esto", y que
  `goback`/`retmon` reactiven ESE contexto antes de usar `sphl`/`ret`,
  no asuman que ya es el correcto), o
- Revisar si `bank$bdos` deberia volver a whoever lo llamo (con un
  `call`+`ret` en vez de salto de cola) para que el cambio a "usuario"
  ocurra en un punto mas controlado, mas cerca de la salida real de
  `bdos:` (justo antes de su `ret` final a la CCP), en vez de en medio
  de la cadena de despacho.

Sesión de hoy en general: gran avance (CCP cargando y ejecutando de
verdad, BDOS alcanzada y procesando), con varios bugs reales de
paginación/pila encontrados y corregidos por el camino -- este último
es el que queda para la próxima sesión.

---

## 2026-09-12 — `RESBDOS.ASM` entero a memoria común (reempaquetado del banco 7)

### El diagnóstico, corregido

Lo de arriba ("contabilidad explícita del contexto") era la vía
equivocada. La causa raíz es más simple y no hace falta inventar nada:
**`RESBDOS.ASM` es, literalmente, lo que DRI titula "Resident Module"**
(cabecera del propio fuente) y está diseñado para vivir en memoria
común — nosotros lo teníamos en memoria banked de sistema
(`$B700-$BC59`). Solo habíamos movido `lstack` al banco 7.

No es una peculiaridad de este hardware. Es la misma condición que en
cualquier CP/M+ bancado de la época: hay código en ese módulo que
cambia de contexto **a mitad de su propia ejecución y sigue ejecutando
después**, así que sus propias instrucciones tienen que seguir estando
donde estaban cuando el contexto cambia. Casos confirmados leyendo el
fuente:

| Rutina | Qué hace |
|---|---|
| `disk$function` | `call bank$bdos` y todo el copiado de FCB/DMA de vuelta que viene **después** (`bank$bdos` acaba en `mvi a,1 / jmp selmemf`: vuelve al llamante con "usuario" ya activo) |
| `parse` | mismo patrón (`call bank$bdos` y sigue) |
| `rb$goback` | restaura `rb$entsp` (el SP real de la CCP, que solo significa algo bajo "usuario") y hace `ret` |
| `qconinx` / `switch1` | seleccionan "usuario" un instante para leer un byte del programa de usuario, con su propio código ejecutándose durante el cambio |
| `rb$func10`, `rb$blk$out1` | llaman a `bank$bdos` y continúan |

Y los datos que se escriben bajo un contexto y se leen bajo el otro
(`rb$aret`, `rb$entsp`, `commonfcb`, `common$dma` — estos dos últimos
con el nombre que ya lo dice) por el mismo motivo.

**`rb$entsp` no necesita ningún apaño.** Una vez el módulo entero es
común, el número guardado se reinterpreta bajo el contexto que esté
activo en el momento del `ret` — que es "usuario", porque `bank$bdos`
ya lo reseleccionó. Que es exactamente como funciona en DRI.

### De dónde salieron los 1369 bytes

El banco 7 son 8192 bytes y parecían no caber. Estaban desperdiciados:

| Hueco recuperado | Bytes | Por qué existía |
|---|---|---|
| `$E100-$E1FF` | 256 | El SCB son 256 B exactos (campo más alto: `bdosadd = scb$pg+0FEh`), pero `ATTR_val` estaba en `$E200` |
| cola de ATTR | 104 | Usa 1+24×81 = 1945 B, ocupaba un slot de 2048 |
| cola de DFILE | 104 | Igual |
| cola del bloque de `boot$1` | 40 | Redondeo |
| `ipchl`/`?pmsg`/`?pdec`/`table10`/`?pderr` | 111 | Estaban en común sin necesitarlo (ver abajo) |

Las rutinas de impresión **no necesitan ser comunes**: sus únicos
llamantes son `boot`/`seldsk` (`BIOSKRNL.ASM`, memoria banked), `?init`
y `?pderr` entre sí — todos con "sistema" seleccionado y ninguno
atraviesa un cambio de banco a mitad de rutina. Se van a `$B700`, la
memoria que `RESBDOS.ASM` deja libre al mudarse.

Igual con `dfctbl`/`xdfctbl` (54 B): son tablas de **solo lectura** que
`disk$function` consulta en su prólogo, bajo "sistema" y **antes** del
`call bank$bdos`. Se quedan en banked, en `$B780`.

### Mapa del banco 7 resultante

| Rango | Tamaño | Contenido |
|---|---|---|
| `$E000-$E0FF` | 256 | SCB |
| `$E100-$E898` | 1945 | `ATTR_val` |
| `$E899-$F031` | 1945 | `DFILE_val` |
| `$F032-$F597` | 1382 | **`RESBDOS.ASM`** (1375 usados) |
| `$F598-$F703` | 364 | Bloque común de `BIOSKRNL.ASM` (361 usados) |
| `$F704-$F7A3` | 160 | `ldccp_real`/`call5_entry`/`lstack` (156 usados) |
| `$F7A4-$F7B7` | 20 | `bank$retaddr`/`bank$savesp`/pila de `?bank` |
| `$F7B8-$F7FF` | 72 | libre |
| `$F800-$F87F` | 128 | `@bnkbf` — sobre los glifos 0-15 (ver el bug de abajo) |
| `$F880-$FFFF` | 1920 | Tabla de fuentes, códigos 16-255 (`font_image.z80`) |

Quedan 8 bytes. Hay dos reservas para cuando haga falta más sitio:

**1. Memoria banked, `$B700` en adelante (1188 bytes contiguos).** Es lo
que `RESBDOS.ASM` deja libre al mudarse, menos lo que hemos vuelto a
meter ahí (`ipchl`..`?pderr` en `$B700`, `dfctbl`/`xdfctbl` en `$B780`);
libre de `$B7B6` a `$BC59`, justo hasta `ccp_image.z80` (`$BD00`). **No
es memoria común** — no sirve para nada que atraviese un cambio de
contexto. Sirve como válvula de escape: buscar algo que esté en el banco
7 sin necesitarlo de verdad y bajarlo aquí, que es exactamente lo que
hemos hecho con las rutinas de impresión y las dos tablas de despacho.

**2. Los bytes de `$F800-$F8FF` dentro de la tabla de fuentes** —
los glifos de los códigos 0-31. **Los 128 primeros ya se han gastado**
en `@bnkbf` (`$F800-$F87F`, códigos 0-15) al reponer los 60 bytes de
`ds ssize*2` de RESBDOS; quedan los 128 de `$F880-$F8FF` (códigos
16-31). No son imprimibles nunca:
`?co` los filtra explícitamente (`cp 20h / ret c`, chario.z80), y los
únicos que escriben en el display file son `print_glyph` (`20h-7Fh`), los
borrados, `scroll` (mueve bytes ya existentes) y el cursor
(`0DBh`/`05Fh`). Reclamarlos es tan sencillo como subir `FIRST` en `genfont.py` y
reajustar su `org`. Como el banco 7 ya tiene MC45 activo para los
bloques 6/7, ahí puede ir **código**, no solo datos.

Requisito para poder reclamarlos, ya hecho: `in_clear_screen` (init.z80)
borraba la pantalla con el **código 0**, o sea que el glifo de
`$F800-$F807` se leía constantemente — era lo que pintaba cada celda en
blanco. Y no coincidía con `cls` (chario.z80, el `^Z` de la emulación
ADM-3A), que ya borraba con el **código 32**: un `^Z` desde la CCP no
dejaba la pantalla en blanco. Ambas usan ahora 32.

**Guardas de tamaño.** Los bloques se colocan con `org` absolutos y los
huecos son de 3-4 bytes, así que cada bloque termina con un
`ds <inicio_del_siguiente>-$`. Si alguno crece de más, el `ds` sale
negativo y **el ensamblado falla** en vez de pisar el bloque siguiente en
silencio. Rellenar el hueco con ceros no cuesta nada: el `.cim` es plano
y esas direcciones ya estaban dentro.

### Bug encontrado de paso: `@BNKBF` arrasaba el SCB

En el SCB de DRI, `scb$base+35h` **no es el buffer**: es un *puntero* de
2 bytes ("Address of 128 Byte Buffer", r/o) donde el BIOS deja la
dirección de su buffer. `SCB.ASM` lo tenía como `@BNKBF equ
scb$base+35h` = `$E035`, pero nuestro código (`move.z80`, `diskio.z80`,
`init.z80`) lo usa como si fuera el buffer en sí (`ld hl,@bnkbf` + `ldir`
de 128 bytes).

Resultado: **cada copia entre bancos arrasaba 128 bytes del SCB** a
partir de `$E035` — `@cbnk` (`$E064`), `olog` (`$E090`), `rlog`
(`$E092`), `hashl`/`hash` (`$E09C`/`$E09D`), `version` (`$E0A1`),
`util$flgs`, `dspl$flgs`, `clp$flgs`, `ccp$comlen`, `ccp$curdrv`,
`ccp$curusr`, `ccp$conbuff` y `ccp$flgs` (`$E0B3`). Y lo usa hasta
`ldccp_real`, o sea en la propia carga de la CCP.

**`@cbnk` es el peor de todos**: es donde `bnksel` apunta cuál es el
contexto activo, y `?bank`/`dup_switcher` lo consultan. Cada `ldir` de
128 bytes por `@bnkbf` lo dejaba con un byte cualquiera del sector
copiado. Encaja con síntomas que veníamos viendo y atribuyendo a otras
cosas — conviene tenerlo presente al interpretar trazas viejas.

Corregido apuntándolo a 128 bytes propios de verdad en `$F778`. Sigue
siendo memoria común, que es lo que exige su función (`?move` escribe
ahí bajo un contexto y lee bajo el otro).

**Pendiente**: si alguna parte de la BDOS llega a leer `scb$base+35h`
esperando el puntero, habrá que además guardar ahí esta dirección en
`?init`. No se ha visto ningún sitio que lo haga, pero no se ha
revisado exhaustivamente.

---

## 2026-09-12 — Fuente real de 256 caracteres (`font_image.z80`)

Sustituye al charset de la ROM del ZX81 replicado ×4 que había de forma
provisional (que no era ASCII: su espacio era la entrada 0 y la 32 caía
en los dígitos).

**Se genera** con `genfont.py` a partir de dos ficheros del proyecto:

| Entrada | Aporta |
|---|---|
| `FONT.BIN` | ASCII imprimible (`$21-$7F`, 95 glifos), redibujado a 7 píxeles de ancho — la columna derecha queda libre como separación entre caracteres |
| `font_atlas_16x16.png` | CP437 completo (128×128, 1 bit, 16×16 celdas de 8×8; **tinta = bit a 1**) |

Manda `FONT.BIN` donde tenga glifo y el atlas rellena el resto. Como
`FONT.BIN` solo define ASCII imprimible (los otros 161 códigos están en
blanco), no hay conflicto: el resultado es **CP437 con el ASCII
redibujado**, que es lo que espera el software de BBS/ANSI.

### Los códigos `$80-$FF` se guardan INVERTIDOS

El detalle que no es evidente y que habría dejado media tabla en
negativo: el hardware complementa los 8 píxeles cuando el código lleva el
bit 7 a 1 — el vídeo inverso clásico del ZX81, **conservado también en
modo 256 caracteres**:

```verilog
if (char_latch_fast[7] && !sfSP_en && !sfHR_en) shift_register <= ~v_dout;
                                                        // SD81.v:1559
```

O sea que `char[7]` hace dos cosas a la vez: elige la mitad alta de la
tabla (bit de dirección, `SD81.v:1089`) **y** invierte lo que se pinta.
Por eso `genfont.py` precomplementa esos 128 glifos y esa mitad de la
tabla se ve llena de `$FF`. Efecto lateral útil: el bloque sólido `$DB`
(el cursor, `CURSOR_BLOCK` en chario.z80) se guarda como ocho `00h`.

Corolario: **el vídeo inverso no se puede hacer con el bit 7** como en un
ZX81 normal (ahí cambiaría de carácter). Va por el byte de atributo.

### Se ensambla en su sitio, no se copia

`font_image.z80` hace `org 0F800h` y se incluye al final de `system.z80`.
Como el `.cim` es plano y se carga desde `$6000`, **el propio cargador
deja la fuente puesta** y `?init` solo tiene que apuntar el registro `I`
(la FPGA lo captura en el refresco: `if (~nRFSH) ROMTABLE[15:8] =
Addr[15:8]`, `SD81.v:456`). Desaparecen `in_copy_font`, `in_blank_sp` y
el equate `CHARSET_SRC`, y con ellos la vieja restricción de "copiar la
fuente ANTES de remapear los bloques 0-2".

`SYSTEM.BIN` pasa de ~38,7 KB a 40 KB justos (`$6000-$FFFF`). Cabe porque
el `LOAD THEN CLEAR 24575` previo deja `RAMTOP` en `$5FFF`, o sea todo
`$6000-$FFFF` libre.

## 2026-09-12 (cont.) — La BDOS se entra con el banco de USUARIO, no el de sistema

Con `RESBDOS.ASM` ya en memoria común, los puntos 16 (`$F24D`) y 17
pasaron: el cambio de contexto dejó de llevarse por delante su propio
código. Pero la ejecución seguía yéndose a la ROM desde `rb$goback`.

**Cómo se vio.** Un breakpoint de escritura en `$0C18` (la ranura de la
pila de la CCP a la que apunta `rb$entsp`) disparó dos veces, y las dos
eran escrituras legítimas. Lo revelador fue comparar el panel de pila
del depurador en ambas paradas, en la MISMA dirección:

| Contexto activo | `$0C18` | `$0C1A` | `$0C1C` |
|---|---|---|---|
| usuario (bloques 0-6 → páginas 8-14) | `$010F` | `$01D2` | `$FFFF` |
| sistema (bloques 0-6 → páginas 0-6) | `$7E09` | `$FD12` | `$3A34` |

`$010F` es la dirección de retorno real que empujó el `CALL $0005` de la
CCP. Y `$7E09, $FD12, $3A34, $0C2A` — la secuencia exacta de direcciones
basura que seguía la traza hasta la ROM — **no era una pila corrompida:
son bytes de la ROM del ZX81**, que es lo que hay en `$0C18` cuando el
bloque 0 apunta a la página 0. Nunca hubo corrupción; se estaba leyendo
la página física equivocada.

**La causa.** `call5_entry` (init.z80) hacía `xor a / call bnksel` para
seleccionar sistema antes de saltar a `bdos:`. Era obligatorio mientras
`bdos:` vivía en memoria banked de sistema, pero con el módulo residente
en el banco 7 sobra — y rompe el diseño de DRI, porque deja "sistema"
seleccionado durante todo el despacho de la BDOS residente.

**El diseño de DRI es el contrario**: la BDOS residente se entra con el
banco de **usuario** todavía puesto. Tiene que ser así porque casi todo
lo que hace antes de llamar a `bank$bdos` se refiere a memoria del
usuario:

- `dad sp / shld rb$entsp` guarda el SP de la CCP, y `rb$goback` lo
  restaura con `sphl / ret`.
- `disk$function` copia el FCB y el DMA *"from the user bank to common
  memory"* (comentario del propio DRI) — con sistema activo copiaría
  memoria ajena.

El único que cambia a sistema es `bank$bdos`, para ejecutar la parte
bancada, y vuelve a usuario él solo antes de devolver el control
(`mvi a,1 / jmp selmemf`). Corregido: `call5_entry` es ahora un `jmp
bdos` a secas.

Nota: el comentario que había en `call5_entry` ya anticipaba esto
(*"esto resuelve la ENTRADA... la vuelta a usuario todavía no está
resuelta"*). La respuesta no era añadir un trampolín de vuelta, sino
quitar el de ida.

### Consecuencias de entrar bajo "usuario": dos cosas más que había que mover

Cambiar el banco de entrada de la BDOS invalida de golpe todo
razonamiento del tipo *"esto se lee bajo sistema, así que puede vivir en
memoria banked"*. Dos casos reales, los dos confirmados en hardware:

**1. `dfctbl`/`xdfctbl` tienen que estar en común.** Se habían dejado en
`$B780` (memoria banked) razonando que `disk$function` solo las consulta
en su prólogo y que ese prólogo corría bajo sistema. Con la BDOS
entrando bajo usuario, ese prólogo (`lxi h,dfctbl-12 / dad b / mov a,m`)
lee `$B780` **bajo usuario**, que es memoria de la CCP — el despacho
entero iba a ciegas. Devueltas al banco 7 (`$F7B8`).

**2. `?mov`/`?xmov` no pueden tocar `@cbnk`.** `?move` restaura el
contexto al terminar leyendo `@cbnk` (`mv$done: ld a,(@cbnk) / call
?bank`, move.z80). Pero la entrada de la tabla de saltos hacía `call
bnksel`, que pone `@cbnk` a 0 **antes** de que `?move` lo lea, así que
`?move` restauraba "sistema" en vez del banco del llamante. Eso era
correcto mientras la residente corría bajo sistema; ahora deja el
contexto equivocado y la cola de `disk$function` acaba en `rb$goback`
leyendo otra vez la ROM. Corregido usando `call ?bank` en esas dos
entradas (mismo tamaño, no actualiza `@cbnk`), que las hace
transparentes al banco. Son las únicas dos entradas de la tabla que
nadie llama desde la TPA, así que no rompe el motivo por el que el resto
sí sincroniza `@cbnk`.

**3. `rb$goback` tiene que garantizar "usuario" él mismo.** El problema
previsto en las entradas de consola (`?cono`, `?const`, `?conin`...:
seleccionan sistema y no lo restauran, porque el driver real `?co`/`?ci`
vive en memoria banked) dio la cara en cuanto la CCP pasó de la función
49 a sacar su prompt. Medido con tres puntos de ruptura en una pasada:
`$F318` disparaba con `A=$01` y `$F24D` después, o sea que en ESA
llamada el banco sí volvía a usuario — el `rb$goback` que aparecía bajo
sistema era **otra llamada distinta**, una de las que llegan ahí sin
pasar por `bank$bdos`:

```
rb$dirstat: call rb$constx    ; -> jmp constf = entrada de la tabla
            jmp rb$sta$ret    ; -> cae en rb$goback, con sistema puesto
```

Arreglado en `rb$goback` con un `mvi a,1 / call selmemf` al principio.
Es el **único punto de salida** de la BDOS residente: a partir de ahí
todo lo que se toca es memoria del programa de usuario (el SP que
restaura `rb$entsp` y la dirección que saca el `ret` final), así que el
banco de usuario tiene que estar puesto sí o sí. Es la misma garantía
que `bank$bdos` ya se da a sí misma al salir. Ojo al orden: `selmemf`
destruye `A` y `HL`, así que los valores de retorno se cargan después.

En el CP/M+ de DRI esto no hace falta porque sus rutinas de consola
están en común y no cambian de banco; el arreglo compensa que las
nuestras no puedan estarlo. Lo ideal sería que cada entrada de la tabla
restaurase el banco del llamante (como hacen ya `?mov`/`?xmov`), pero
son muchas y el bloque duplicado `$7E00-$7FFF` va justo de espacio.

### Causa raíz de verdad: `?mov` destruía HL antes de llamar a `?move`

Todo lo anterior (bancos que no se restauran) es real, pero el fallo que
nos tenía dando vueltas era otro, y llevaba ahí desde el principio.

La convención del BIOS de CP/M 3 para MOVE es **`HL` = destino, `DE` =
origen, `BC` = contador**. Pero `?bank` termina con `ld
hl,(bank$retaddr) / jp (hl)` — **destruye `HL`**. Y la entrada de la
tabla era:

```
?mov:   xor  a
        call bnksel      ; -> ?bank, que se lleva HL por delante
        jmp  ?move
```

Así que `?move` recibía como destino la dirección del propio `jmp ?move`
(`$7EEC`) en lugar del destino real. La primera copia de FCB de la BDOS
(`cpyfcbin`: `lxi h,commonfcb / lxi b,36 / call movef`) escribía por
tanto **36 bytes justo encima de la tabla de saltos**: `?tim`, `?bnksl`,
`?stbnk`, `?xmov` y `?ldccp`.

Con `?bnksl` machacada, **todos los cambios de banco posteriores saltan a
basura** — de ahí las direcciones sin sentido que salían de
`bank$retaddr` (`$FD12`, `$7E09`...) y que llevábamos sesiones
persiguiendo como si fueran corrupción de pila.

Corregido salvando `HL` en banco 7 alrededor del cambio de banco. `?xmov`
no lo necesita (XMOVE recibe los bancos en `B` y `C`).

**Lección para el futuro**: cualquier entrada de la tabla de saltos cuya
rutina reciba parámetros en `HL` está expuesta a esto. Hoy solo MOVE los
recibe así, pero conviene recordarlo — `?bank` no es transparente a los
registros: preserva `AF`/`BC`/`DE` pero no `HL`.

### La página 0 es la ROM: rellenarla de HALT

Bajo "sistema", `?bank` mapea `BANK0_BASE+bloque`, o sea la **página 0 en
el bloque 0** — y la página 0 del booster es la ROM del ZX81. Eso hacía
que cualquier salto perdido a memoria baja acabara **ejecutando** la ROM,
que sigue viva y se queda en su bucle de teclado: el fallo se disfrazaba
de *"se ha colgado"* en vez de parar donde se produjo, y eso nos ha
costado varias sesiones de diagnóstico.

`?init` la rellena ahora con `$76` (HALT), de modo que un salto perdido
para la CPU en seco y el depurador da la dirección exacta. Se hace por
ventana temporal (mapear la página 0 en el bloque 6, rellenar, restaurar)
porque a esas alturas el bloque 0 ya tiene la página 8.

### Nos faltaba un paso de GENSYS: el vector de error del SCB

Con `?mov` arreglado, la ejecución llegó mucho más lejos y murió de otra
cosa. El HALT de la página 0 hizo su trabajo y la traza fue directa:

```
$96C2  C4FBE0   CALL NZ,error
error  $E0FB  00  NOP      <- ceros
ATTR_val $E100 00 NOP      <- y sigue por atributos y pantalla
```

`error equ scb$pg+0fbh` (`$E0FB`) es una ranura del SCB que **tiene que
contener un `JMP error$sub`**, y estaba a ceros. El propio `BDOS.ASM` lo
explica:

> *"error$sub is referenced indirectly by the SCB ERROR field in RESBDOS
> ... This value is converted to the actual address of error$sub **by
> GENSYS**"*

O sea: en un CP/M+ real lo rellena **GENSYS**, el generador de sistema de
DRI. Como no pasamos por GENSYS, hay pasos suyos que tenemos que hacer a
mano, y este se nos había escapado. `?init` lo instala ahora.

**Conviene buscar si hay más ranuras así.** Cualquier campo del SCB que
DRI describa como "rellenado por GENSYS" es un candidato al mismo
problema, y el síntoma es siempre el mismo: un salto a ceros que no
revienta, sino que sigue ejecutando lo que venga detrás.

**Y el error en sí era correcto**: la traza muestra `seldsk` consultando
`@dtbl`, saliendo unidad nula, y la BDOS levantando `sel$error` con
`C=$04` = *Invalid Drive*. Es la respuesta buena mientras no haya
unidades de disco reales. Lo que faltaba no era el error, era el sitio al
que saltar para informarlo.

### El SCB estaba desplazado $9C bytes: "base de la página" != "base del SCB"

Con el vector de error puesto salió el mensaje `CP/M Error On Z: Invalid
Drive1?` — la BDOS funcionando de punta a punta por primera vez, pero con
dos anomalías (unidad `Z` en vez de `A`, y una cola `1?`). Las dos tienen
la misma causa.

`SCB.ASM` tenía `scb$base equ 0E000h`, o sea la base de la **página** del
SCB. Pero los offsets de ese fichero (`@CIVEC=+22h`, `@MXTPA=+62h`...)
son del **SCB público**, que empieza `$9C` bytes dentro de la página; lo
de debajo son variables internas de la BDOS. Resultado: **todos los
símbolos `@` apuntaban $9C bytes por debajo de su sitio.**

Tres fuentes independientes coinciden en el `$9C`:

| Fuente | Evidencia |
|---|---|
| `CCP3.ASM:162` | `pag$off equ 09ch` — todos sus campos son `pag$off+n` |
| `BDOS.ASM:119` | `SCB equ scb$pg+09ch` |
| Comprobación cruzada | `conwidth` es `scb$pg+0B6h` para la BDOS y `pag$off+1Ah` para la CCP → `$9C+$1A = $B6` |

Y con la base correcta encajan dos campos que lo rematan:

- `@MXTPA` = base+62h = **`$E0FE`** = `bdosadd` de la BDOS — el mismo campo.
- `?ERJMP` = base+5Fh = **`$E0FB`** = `error` de la BDOS, o sea **la
  ranura del vector de error que acabábamos de instalar a mano**.
  `SCB.ASM` ya la documentaba; la teníamos apuntando a `$E05F`.

Los cinco vectores de redirección también encajan exactos: `@CIVEC`…
`@LOVEC` pasan a `$E0BE`-`$E0C7`, que son `conin$rflg`…`lstout$rflg` de
la BDOS.

**Por qué la consola funcionaba igualmente**: `?init` escribía los
vectores en `$E022` y `BIOSKRNL.ASM` los leía del mismo sitio
equivocado — consistente entre ellos, pero la BDOS usaba las direcciones
buenas para esos mismos campos. Cada uno hablaba de un SCB distinto.

Lo demás cae solo: la CCP leía `bdosbase` (`pag$off-4`) y
`conwidth`/`conpage` a cero, con lo que su arranque iba a ciegas; y
`bdos$flags` sin inicializar hacía que `errflg` tomara la rama larga y
compusiera ese `1?` con dígitos sin sentido.

Corregido con una línea (`scb$base equ 0E09Ch`). `@cbnk` sigue en
`$E064` sin conflicto: la BDOS no usa ningún campo por debajo de `$E090`.
`@BNKBF` se queda apuntando al buffer real en `$F800` (nuestro código lo
usa como buffer, no como puntero), y `?init` deja además la dirección en
la ranura `scb$base+35h` que le corresponde.

### `$0004` sin inicializar: la unidad "Z" y el "1?" eran el mismo byte

Corregida la base del SCB, la salida no cambio ni un caracter — util en
si mismo: descarta esa via como causa (aunque el arreglo era correcto y
necesario, porque BIOS y BDOS usaban direcciones distintas para los
mismos campos; simplemente `?init` y `BIOSKRNL` se movian juntos y por
eso "funcionaba").

Dos breakpoints de escritura lo cerraron:

- **`$B1AA` (`adrive`)**: dos disparos. Uno con `PC=$212B`, que resulta
  ser **el propio cargador** (`IN A,($A7)` / `LD (DE),A` / espera en
  `$AF`, con MC45 aun apagado): es el `db 0ffh` del fichero llegando a
  memoria. El otro con `PC=$A754`, que es `disk$select` de la BDOS
  guardando la unidad **que le han pedido**. O sea: nadie corrompe nada,
  la BDOS recibe el 25 de verdad.
- **`$E0F3` (`bdos$flags`)**: solo la escritura del cargador, nunca se
  pone a 1. Eso descarta que el `1?` venga de la rama larga de `errflg`.

Releyendo la pantalla con eso en mente, el `1?` **no es el final de cada
mensaje, es el principio del siguiente**: `errflg` empieza con `crlf`,
asi que la CCP imprime su prompt, queda pegado a lo anterior, y luego
viene el salto de linea y el error. Por eso la ultima linea no lo lleva.

Y ahi encaja todo: **`$19` = `0001 1001`**. La posicion **`$0004`** de la
pagina cero guarda `(usuario << 4) | unidad`. Nibble alto = 1 (el "1"
del prompt) y byte entero = 25 (la unidad "Z" del error). **Las dos
anomalias salian del mismo byte sin inicializar.**

`set$jumps` (BIOSKRNL.ASM) escribe `$0000-$0002` y `$0005-$0007` pero
nunca `$0003` (IOBYTE) ni `$0004`. Anadido. Los 7 bytes que hacian falta
en el bloque comun salieron de reducir `boot$stack` de 64 a 56 (la cadena
mas profunda que lo usa es `boot$1 -> set$jumps -> ?bnksl`, y `?bank`
tiene pila propia, asi que no pasa de 3-4 niveles).

**Lección**: dos sintomas que parecian independientes (una letra de
unidad y una cola de texto rara) eran el mismo byte. Merece la pena
buscar el denominador comun antes de atacarlos por separado.

### `?move` ignoraba la especificación de MOVE/XMOVE (el FCB llegaba de otro banco)

Ni la base del SCB ni `$0004` cambiaron la salida. Lo que la cerró fue
leer el **panel de pila** del depurador en el momento del fallo, que era
la cadena de llamadas completa:

```
$A77B  $A7E2  $AAA6  $B13B  $F318  $F24D  $0AC5
```

Traducida con el `.lst`: `$AAA6` es el retorno de **`reselectx`** (la
rutina que selecciona la unidad **a partir del byte 0 del FCB**), y
`$B13B` es `goback`. Y `$0AC5` no era una dirección de retorno sino un
**dato**: en `CCP3.lst` es `subfcb: db 1,'$$$     SUB',0`, el FCB con el
que la CCP busca el fichero de SUBMIT al arrancar.

O sea: **la CCP pasa un FCB con el byte de unidad = 1 (unidad A), y la
BDOS acaba seleccionando la 25.** El FCB se corrompía por el camino.

Ese camino es `cpyfcbin` (RESBDOS.ASM):

```
cpyfcbin:  lxi h,commonfcb
           lxi b,36
           call movef        ; <- sin xmovef delante
```

Y nuestro `?move` **siempre** hacía la copia entre bancos usando
`xmv$sbnk`/`xmv$dbnk`, que fuera de una secuencia XMOVE+MOVE contienen
valores rancios. Resultado: leía el FCB del banco equivocado.

**La especificación de DRI es la contraria**: MOVE copia **dentro del
banco actual**, y solo usa bancos distintos si XMOVE se llamó
inmediatamente antes — y XMOVE afecta **solo al siguiente** MOVE.

Corregido: `?xmove` marca un flag (`xmv$pend`), `?move` lo consulta, hace
la copia entre bancos solo en ese caso y lo limpia; si no, un `ldir`
normal. Añadida además la guarda `BC=0 -> ret`, porque un `LDIR` con
`BC=0` copiaría 65536 bytes.

**Encaja con la decisión de entrar en la BDOS bajo el banco de usuario**:
el FCB está en el banco de usuario (mapeado) y `commonfcb` en el banco 7
(siempre mapeado), así que una copia normal es exactamente lo que hace
falta. Por eso DRI no pone un `xmovef` ahí.

**Lección de método**: el panel de pila del depurador en el punto del
fallo valía más que los tres breakpoints de escritura anteriores. Los
dos símbolos del medio (`reselectx`, `goback`) identificaron el
mecanismo, y el de abajo identificó el dato exacto.

### `move.z80` estaba dentro del bloque duplicado del switcher

Tras el arreglo de MOVE/XMOVE la unidad cambio de `Z` (25) a `V` (21):
la copia del FCB era distinta, pero seguia trayendo basura. Un solo
breakpoint lo cerro -- **`$F23D`**, el `call movef` de `cpyfcbin`:

| Dato | Valor | Veredicto |
|---|---|---|
| `DE` | `$0ABC` (`scbadd` de la CCP) | correcto |
| Block Page | 0:8, 1:9, … | **usuario**, correcto |
| `commonfcb` tras la copia | **36 bytes de `$76`** | basura |

`$76` es HALT, o sea **el relleno que pusimos en la pagina 0**. Y la
pagina 0 solo es alcanzable con *sistema* activo. Si la copia hubiera
sido el `LDIR` normal bajo usuario habria leido la CCP; luego tomo el
camino de bancos, con `xmv$sbnk` = 0.

Mirando donde habian caido esas variables aparecio la causa real:

```
xmv$dbnk = $7F1C   xmv$sbnk = $7F1D   xmv$pend = $7F1E
?xmove   = $7F1F   ?move    = $7F28
```

**Todo eso esta dentro del bloque duplicado del switcher
(`$7E00-$7FFF`)**. Faltaba un `org` al final de `bank.z80`: el bloque
duplicado son 512 bytes, la tabla de saltos acaba sobre `$7F1C`, y
`move.z80` -- el primer fichero incluido despues -- empezaba justo ahi.
Contradecia ademas lo que dice la cabecera del propio `bank.z80`
(*"?xmove/?move … viven en zona normal, no aqui"*).

**Por que es grave**: la zona duplicada vive en el **bloque 3, que
`?bank` SI repagina**. O sea que esas variables estaban duplicadas, con
una copia por contexto:

- `?move` escribia `mv$de`/`mv$hl`/`mv$cnt`, hacia `call ?bank` para
  pasar al otro contexto, y luego los leia de la **otra copia** -- la
  que `dup_switcher` dejo congelada en el arranque.
- `?xmove` ponia `xmv$pend`/`xmv$sbnk` en una copia y `?move` los
  consultaba en la otra.

Corregido con `org 08000h` al final de `bank.z80` ($8000 es el primer
byte fuera del bloque duplicado). Todo lo que viene detras se desplaza
~228 bytes; anadida una guarda `ds 08900h-$` en `system.z80` antes de
`BDOS.ASM`, porque dos `org` absolutos que se solapan **no dan error**:
el segundo pisa al primero en silencio.

La guarda salto a la primera: el XIOS se pasaba de `$8900` por 38 bytes.
Resuelto subiendo una pagina las dos referencias que dependian de ahi:

| Que | Antes | Ahora |
|---|---|---|
| `org` de `BDOS.ASM` | `$8900` | `$8A00` |
| `org` de las rutinas de impresion (`BIOSKRNL.ASM`) | `$B700` | `$B800` |

(La BDOS termina alineada a pagina respecto a su base, asi que su final
sube de `$B6FF` a `$B7FF` y las rutinas de impresion van justo detras.
`ccp_image` sigue en `$BD00`, sin conflicto.)

**Lección**: un `org` que abre una zona especial necesita SIEMPRE su
`org` de cierre. Aqui la zona se "cerraba" sola por llegar al final del
fichero, y lo que vino detras se colo dentro sin que nada lo avisara.

El mismo descuido aparecio acto seguido en `init.z80`: su bloque del
banco 7 (`org 0F704h`) tampoco cerraba, y como es el ultimo fichero del
XIOS el contador de posicion se quedaba en `$F7A4` al terminar. La
guarda de `system.z80` comparaba entonces contra `$F7A4` en vez de
contra el final real del XIOS, dando un "Value error" enganoso. Anadido
`org init$cseg$save`.

**Auditoria de todos los `org` del proyecto** tras el segundo caso, para
no repetirlo. Cada apertura con su cierre:

| Fichero | Abre | Cierra |
|---|---|---|
| `BIOSKRNL.ASM` | `$F598` (boot$1) | `org 06058h` |
| `BIOSKRNL.ASM` | `$B800` (rutinas de impresion) | `org bioskrnl$cseg$save` |
| `BIOSKRNL.ASM` | `$E064` (`@cbnk`) | `org 062E9h` |
| `bank.z80` | `$F7A4` (vars de `?bank`) | `org 062E9h` |
| `bank.z80` | `$7E00` (switcher) | `org 08000h` |
| `init.z80` | `$F704` (ldccp/call5/lstack) | `org init$cseg$save` |
| `RESBDOS.ASM` | `$F7B8` (dfctbl) | `org resbdos$cseg$save` |

Los que NO cierran son correctos porque lo siguiente fija la posicion
explicitamente: `RESBDOS.ASM` (`$F032`) lo sigue `ccp_image.z80` con su
propio `org 0BD00h`, y a este `font_image.z80` con `org 0F880h`.
Y la guarda `ds <siguiente>-$` demostro su valor dos veces seguidas: una
para detectar el desbordamiento y otra para confirmarlo corregido.

### La CCP leia el SCB de la pagina cero: faltaba otro campo de GENSYS

Con la ruta de copia ya correcta (banco de usuario y `commonfcb` con el
nombre `$$$     SUB` exacto), solo fallaba el **byte 0** del FCB: llegaba
`$FF` en vez de `$01`. Un breakpoint de escritura en `$0AC5` lo cazo en
un tiro:

```
$0190  2EEC   LD L,$EC      ; solo carga L: H viene de "scbaddr"
$0193  7E     LD A,(HL)     ; HL = $00EC  <- H = 0
$0194  02     LD (BC),A     ; BC = $0AC5 (subfcb[0]), A = $FF
```

La CCP lee **todos** los campos del SCB con el patron `mvi l,offset /
mov a,m`, usando solo la parte **alta** de `scbaddr` como pagina. Y
`scbaddr` tenia `H = $00`, asi que leia la pagina cero. El campo que
queria era `temp$drive` (`$E0EC`) para poner la unidad en el byte 0 de su
FCB de `$$$.SUB` -- **la logica de la CCP era correcta todo el tiempo**,
solo leia de la pagina equivocada.

`scbaddr` sale de la funcion 49 al arrancar:

```
lxi d,scbadd / mvi c,scbf / call bdos / shld scbaddr
```

y `scbad equ pag$off+03ah` -> el campo **`$E0D6`**, *"system control
block address"*. Estaba a ceros: **otro campo que rellena GENSYS** y que
no habiamos puesto. `?init` lo inicializa ahora con `scb$base`.

De paso, la geometria de consola (`conwidth` `$E0B6`, `conpage` `$E0B8`),
que la CCP lee en su `scbinit` para calcular columnas del catalogo y
tamano de pagina, y que tambien estaba a cero.

**Patron a vigilar**: ya van tres campos del SCB que en un CP/M+ real
deja puestos GENSYS y aqui hay que poner a mano (`?ERJMP`, la direccion
del SCB, la geometria de consola). Conviene revisar la lista completa de
campos del SCB con valores iniciales antes de dar por cerrada esta fase,
porque el sintoma siempre es el mismo: un cero que no revienta, sino que
desvia la lectura o la ejecucion a un sitio plausible.

### HITO: prompt `A>` y teclado funcionando

Con el campo `$E0D6` inicializado, la CCP arranca del todo: sale el
prompt **`A>`** y se puede escribir. Es el sistema entero funcionando de
punta a punta -- arranque, paginacion bancada, CCP cargada y ejecutandose
en su TPA, BDOS residente en memoria comun, cambio de contexto en cada
llamada a la BDOS, consola y teclado.

**La cadena de bugs que hubo que desmontar para llegar aqui**, en orden,
porque cada uno tapaba al siguiente:

| # | Bug | Por que costo encontrarlo |
|---|---|---|
| 1 | `RESBDOS.ASM` en memoria bancada en vez de comun | El modulo desaparecia bajo sus propios pies al cambiar de contexto |
| 2 | `call5_entry` seleccionaba sistema al entrar en la BDOS | Justo al reves de lo que hace DRI; invalidaba todo el trabajo con memoria de usuario |
| 3 | `?mov` destruia `HL` (la convencion de MOVE lo usa como destino) | La primera copia de FCB escribia 36 bytes ENCIMA de la tabla de saltos |
| 4 | `move.z80` caia dentro del bloque duplicado del switcher | Faltaba el `org` de cierre en `bank.z80`; sus variables quedaban duplicadas por contexto |
| 5 | `?move` ignoraba la especificacion MOVE/XMOVE | Copiaba siempre entre bancos, con valores rancios |
| 6 | El camino rapido de MOVE, puesto en el sitio equivocado | Lo metí dentro de `?move`, a donde solo se llega habiendo cambiado ya de banco |
| 7 | Falta el vector de error del SCB (`?ERJMP`) | Trabajo de GENSYS; un salto a ceros que no revienta |
| 8 | Falta la direccion del SCB (`$E0D6`) | Idem; la CCP leia todo el SCB de la pagina cero |

Tres ayudas de diagnostico resultaron decisivas y merece la pena
conservarlas:

- **Rellenar la pagina 0 con `$76` (HALT)**. Antes, cada salto perdido
  caia en codigo de ROM que *sigue funcionando*, y el fallo se
  disfrazaba de "se ha colgado". Con HALT la CPU para en seco.
- **El panel de pila del depurador** traducido con `system.lst` y
  `CCP3.lst`. Identifico el mecanismo (`reselectx`) y el dato exacto
  (`subfcb`) cuando tres breakpoints de escritura no habian dado nada.
- **Las guardas `ds <siguiente>-$`**. Dos `org` absolutos que se solapan
  no dan ningun error: el segundo pisa al primero en silencio.

### Pendiente

1. **Teclado**: hay comportamientos que repasar (primer sintoma tras el
   hito).
2. **Opcion B**: envoltorio de la tabla de saltos para que una llamada al
   BIOS no altere el banco visible. Sigue siendo necesaria por si misma
   -- ademas arregla el caso de que un programa de usuario llame a la
   tabla directamente, que hoy no podria volver nunca.
3. **Repasar la lista completa de campos del SCB con valor inicial**, en
   vez de descubrirlos de uno en uno. Ya van tres.
4. **Unidades de disco reales** (`@dtbl` con una DPH de verdad, disco RAM
   o SD). Hasta entonces *Invalid Drive* es la respuesta correcta.
5. **`?time`/RTC**: sigue siendo un no-op en `move.z80`.

### Ficheros tocados

| Fichero | Cambio |
|---|---|
| `init.z80` | `ATTR_val` `$E200`→`$E100`; `DFILE_val` `$EA00`→`$E899`; `org` de `ldccp_real` `$F400`→`$F6C4`; guarda |
| `chario.z80` | `DFILE` `$EA00`→`$E899` (duplicado de `DFILE_val`, tienen que coincidir) |
| `BIOSKRNL.ASM` | `org` del bloque común `$F200`→`$F558`; `ipchl`..`?pderr` a `$B700`; guarda |
| `bank.z80` | `org` de las variables de `?bank` `$F600`→`$F764`; guarda |
| `RESBDOS.ASM` | `org 0F032h` al principio (módulo entero a común); `dfctbl`/`xdfctbl` a `$B780`; guarda |
| `SCB.ASM` | `@BNKBF` `$E035`→`$F778`; cabecera corregida |
| `system.z80` | `include "font_image.z80"` al final |
| `font_image.z80` | **nuevo**, generado (2048 B en `$F800`) |
| `genfont.py` | **nuevo**, generador de la fuente (sin dependencias: decodifica el PNG con `zlib`) |

Ni una línea de lógica cambia: todos los usos de `DFILE` son simbólicos
y `ATTR_val` solo se referencia en el borrado de `?init`.

---

## Referencia: mapa completo de la página del SCB ($E000-$E0FF)

Generado cruzando las tres fuentes que describen esa página. **Las tres
concuerdan campo por campo**, lo que confirma que la base del SCB público
es `$E09C` (`BDOS.ASM` usa `scb$pg+n` con `scb$pg=$E000`; `CCP3.ASM` usa
`pag$off+n` con `pag$off=$9C`; `SCB.ASM` usa `scb$base+n`).

Equivalencias que lo demuestran: `conin$rflg`=`@CIVEC`, `dmaad`=`@CRDMA`,
`olddsk`=`@CRDSK`, `fx`=`@FX`, `multcnt`=`@MLTIO`, `errormode`=`@ERMDE`,
`error`=`?ERJMP`, `bdosadd`=`top$tpa`=`@MXTPA`.

La columna "quién lo pone" es lo que importa: lo que está **vacío** no lo
inicializa nadie, y en un CP/M+ real lo dejaría puesto GENSYS.

| Dir | BDOS.ASM | CCP3.ASM | SCB.ASM (DRI) | Quién lo pone |
|---|---|---|---|---|
| `$E090` | `olog` | `olog` | `—` |  |
| `$E092` | `rlog` | `rlog` | `—` |  |
| `$E098` | `—` | `bdosbase` | `—` |  |
| `$E09C` | `SCB` | `hashl` | `—` |  |
| `$E09D` | `hash` | `hash` | `—` |  |
| `$E0A1` | `version` | `bdos$version` | `—` | CCP scbinit |
| `$E0A2` | `util$flgs` | `util$flgs` | `—` |  |
| `$E0A6` | `dspl$flgs` | `dspl$flgs` | `—` |  |
| `$E0AA` | `clp$flgs` | `clp$flgs` | `—` |  |
| `$E0AB` | `—` | `clp$drv` | `—` |  |
| `$E0AC` | `clp$errcde` | `prog$ret$code` | `—` |  |
| `$E0AE` | `ccp$comlen` | `multi$rsx$pg` | `—` |  |
| `$E0AF` | `ccp$curdrv` | `ccpdrv` | `—` |  |
| `$E0B0` | `ccp$curusr` | `ccpusr` | `—` |  |
| `$E0B1` | `ccp$conbuff` | `ccpconbuf` | `—` |  |
| `$E0B3` | `ccp$flgs` | `ccpflag1` | `—` |  |
| `$E0B4` | `—` | `ccpflag2` | `—` |  |
| `$E0B5` | `—` | `ccpflag3` | `—` |  |
| `$E0B6` | `conwidth` | `conwidth` | `—` | ?init (COLS-1) |
| `$E0B7` | `column` | `concolumn` | `—` |  |
| `$E0B8` | `conpage` | `conpage` | `—` | ?init (ROWS) |
| `$E0B9` | `conline` | `conline` | `—` |  |
| `$E0BA` | `conbuffadd` | `conbuffer` | `—` |  |
| `$E0BC` | `conbufflen` | `conbuffl` | `—` |  |
| `$E0BE` | `conin$rflg` | `conin$rflg` | `@CIVEC` | ?init ($8000) |
| `$E0C0` | `conout$rflg` | `conout$rflg` | `@COVEC` | ?init ($8000) |
| `$E0C2` | `auxin$rflg` | `auxin$rflg` | `@AIVEC` | ?init ($8000) |
| `$E0C4` | `auxout$rflg` | `auxout$rflg` | `@AOVEC` | ?init ($8000) |
| `$E0C6` | `lstout$rflg` | `listout$rflg` | `@LOVEC` | ?init ($8000) |
| `$E0C8` | `page$mode` | `page$mode` | `—` |  |
| `$E0C9` | `pm$default` | `page$def` | `—` |  |
| `$E0CA` | `ctlh$act` | `ctlh$act` | `—` |  |
| `$E0CB` | `rubout$act` | `rubout$act` | `—` |  |
| `$E0CC` | `type$ahead` | `type$ahead` | `—` |  |
| `$E0CD` | `contran` | `contran` | `—` |  |
| `$E0CF` | `conmode` | `con$mode` | `—` | CCP scbinit |
| `$E0D1` | `—` | `ten$buffer` | `—` | ?init (puntero a @bnkbf) |
| `$E0D3` | `outdelim` | `outdelim` | `—` | CCP scbinit |
| `$E0D4` | `listcp` | `listcp` | `—` |  |
| `$E0D5` | `qflag` | `q$flag` | `—` |  |
| `$E0D6` | `scbadd` | `scbad` | `—` | ?init (scb$base) |
| `$E0D8` | `dmaad` | `dmaad` | `@CRDMA` | BDOS (func 26 / reset) |
| `$E0DA` | `olddsk` | `seldsk` | `@CRDSK` | BDOS |
| `$E0DB` | `info` | `info` | `@VINFO` | BDOS |
| `$E0DD` | `resel` | `resel` | `@RESEL` | BDOS |
| `$E0DE` | `relog` | `relog` | `—` |  |
| `$E0DF` | `fx` | `fx` | `@FX` | BDOS |
| `$E0E0` | `usrcode` | `usrcode` | `@USRCD` | BDOS |
| `$E0E1` | `dcnt` | `dcnt` | `—` | BDOS |
| `$E0E3` | `—` | `searcha` | `—` | BDOS |
| `$E0E5` | `searchl` | `searchl` | `—` | BDOS |
| `$E0E6` | `multcnt` | `multcnt` | `@MLTIO` | CCP scbinit |
| `$E0E7` | `errormode` | `errormode` | `@ERMDE` | CCP scbinit |
| `$E0E8` | `searchchain` | `drv0` | `—` |  |
| `$E0E9` | `—` | `drv1` | `—` |  |
| `$E0EA` | `—` | `drv2` | `—` |  |
| `$E0EB` | `—` | `drv3` | `—` |  |
| `$E0EC` | `temp$drive` | `tempdrv` | `—` | BDOS |
| `$E0ED` | `errdrv` | `patch$flag` | `@ERDSK` | BDOS |
| `$E0F0` | `media$flag` | `—` | `@MEDIA` |  |
| `$E0F3` | `bdos$flags` | `—` | `@BFLGS` |  |
| `$E0F4` | `stamp` | `date` | `@DATE` |  |
| `$E0F6` | `—` | `—` | `@HOUR` |  |
| `$E0F7` | `—` | `—` | `@MIN` |  |
| `$E0F8` | `—` | `—` | `@SEC` |  |
| `$E0F9` | `commonbase` | `com$base` | `—` |  |
| `$E0FB` | `error` | `error` | `?ERJMP` | ?init (jmp error$sub) |
| `$E0FE` | `bdosadd` | `top$tpa` | `@MXTPA` | ?init (call5_entry) |

Regenerar con `scratchpad/scbmap.py` si cambian los equates de alguno de
los tres ficheros.

### Estado del SCB: cerrado salvo un campo

Verificado en hardware con el prompt en pantalla (volcado de
`$E000-$E0FF`), todos los campos que `?init` inicializa llegan correctos:

| Campo | Valor | |
|---|---|---|
| `?ERJMP` `$E0FB` | `C3 7C 8A` = `jmp error$sub` | ✓ |
| `@MXTPA` `$E0FE` | `58 F7` = `call5_entry` | ✓ |
| `@BNKBF` ptr `$E0D1` | `00 F8` = `$F800` | ✓ |
| `scbadd` `$E0D6` | `9C E0` = `$E09C` | ✓ |
| `conwidth` `$E0B6` | `4F` = 79 | ✓ |
| `conpage` `$E0B8` | `18` = 24 | ✓ |
| Los 5 vectores `$E0BE-$E0C7` | `00 80` ×5 | ✓ |
| `outdelim` `$E0D3` (lo pone la CCP) | `24` = `'$'` | ✓ |
| `bdos$version` `$E0A1` (idem) | `31` | ✓ |

Anadido ademas **`commonbase` (`$E0F9`) = `$E000`**: la CCP guarda su
byte alto en su variable `banked`, y con el campo a cero creia que el
sistema no es bancado.

De los ~40 campos que no inicializa nadie, en todos los demas el cero es
un valor por defecto razonable (flags apagados, contadores a cero).

Anadido tambien **`rubout$act` (`$E0CB`) = `$FF`**, a raiz de un sintoma
de teclado que resulto no ser del teclado: `SHIFT+0` (DEL) *mostraba* el
caracter en vez de borrarlo. La BDOS decide asi, en el editor de linea de
la funcion 10:

```
cpi rubout / LDA RUBOUT$ACT / INR A / JZ DO$CTLH
```

Con `$FF` trata el `$7F` como retroceso y borra; con cualquier otro valor
hace el *rubout* clasico de teletipo, que **imprime** el caracter
borrado -- correcto sobre papel continuo, absurdo en pantalla.
`ctlh$act` (`$E0CA`) se deja a 0, que es justo lo contrario y es lo
deseado: Ctrl-H hace un retroceso normal.

**Único pendiente: `bdosbase` (`$E098`)**. La CCP lo guarda en `realdos`
y solo lo usa en la rutina XCOM, al cargar programas transitorios.
Deliberadamente sin fijar: cae por debajo de la base del SCB publico
(`scb$pg+$98`), la BDOS ni lo nombra, y no hay forma de comprobar el
valor correcto hasta que se pueda ejecutar un `.COM`. Fijarlo entonces,
con la prueba delante, en vez de adivinarlo ahora.


---

## Teclado: bloqueo mutuo entre `enter_used` y `?cist`

Sintomas: tras probar "ENTER+tecla" (simbolos), **ni ENTER solo ni
SHIFT+ENTER volvian a responder nunca**. Las teclas directas, SHIFT+tecla
y ENTER+tecla seguian bien.

`enter_used` (chario.z80) marca "este ENTER ya se consumio como
modificador", para que al soltarlo no genere ademas un CR. Se pone a 1 en
`ck_mods` y se limpiaba **solo** en `ck_clr`, que esta dentro de `kbget`.

El bloqueo: con `enter_used`=1, **`?cist` responde "no hay tecla"** para
ENTER. La BDOS solo llama a `?ci` cuando `?cist` dice que si, asi que
`kbget` no llega a ejecutarse nunca -- y por tanto `ck_clr` tampoco. El
flag se quedaba a 1 de forma permanente.

Arreglado limpiando el residual en `?cist` cuando ENTER esta **suelto**,
que es un estado que esa rutina si puede observar porque se sondea
constantemente.

**Lección**: un flag que se pone en un camino y se limpia en otro es
seguro solo si el segundo camino se alcanza siempre. Aqui el propio flag
cerraba la puerta por la que habia que salir a limpiarlo.


---

## Opcion B implementada: `biosw`, envoltorio de la E/S de caracter

Sintoma que la hizo obligatoria: con el prompt en pantalla, **toda orden
daba `?`** (`DIR` -> `DIR?`, `E:` -> `?`). El `?` es la respuesta normal
de CP/M a "orden no encontrada", pero `DIR` es una orden interna y `E:`
un cambio de unidad: ninguna deberia llegar ahi.

La pista la dio volcar el buffer de consola de la CCP (`$0B4A`): salian
**todo `$76`**, o sea el relleno de HALT de la pagina 0. Al pausar, el
bloque 0 tenia la pagina 0 -- estabamos en **sistema**.

Y no era casualidad del momento de pausa: mientras la BDOS espera una
tecla **sondea `?cist` continuamente** a traves de la tabla de saltos, y
esas entradas seleccionan sistema y **no lo restauran**. Asi que el
sistema pasaba casi todo el tiempo en sistema. Entonces la copia de
vuelta de la funcion 10 (`jmp movef` al final de `rb$func10`) escribia la
linea leida en la pagina 0 en vez de en el buffer de la CCP: se veia lo
tecleado (el eco lo hace la BDOS al editar) pero **la CCP recibia un
buffer sin actualizar**, y de ahi que `eoc` encontrara basura y toda
orden diera `?`.

### Que hace

Las 10 entradas de caracter pasan de `xor a / call bnksel / jmp rutina`
(salto de cola) a `ld hl,rutina / jmp biosw` (mismo tamano). El
envoltorio guarda el banco del llamante, cambia a sistema, **llama** a la
rutina real y **restaura** el banco antes de volver.

En el CP/M+ de DRI esto no hace falta porque toda la E/S de caracter es
residente (ver los `cseg`/`dseg` de `BIOSKRNL.ASM`) y no hay cambio de
banco ninguno. Aqui el driver real (`?co`/`?ci`, chario.z80) son 789
bytes que no caben en el banco 7, asi que se reproduce la **garantia**
("una llamada al BIOS no altera el banco visible") en vez de la
estructura.

**Detalle critico**: `biosw` cambia a pila comun ANTES de tocar el
paginado. La pila del llamante esta en su banco, asi que un `push` antes
del cambio y su `pop` despues caerian en paginas fisicas distintas --
exactamente el error que ya nos mordio en `?bank`.

Solo se envuelven las de caracter: intercambian datos por registros
(caracter en `C`, resultado en `A`) y no usan `HL`, que es lo que el
envoltorio necesita para saber a donde saltar. Las de disco no se
envuelven -- las llama la BDOS bancada, que ya esta en sistema, y ademas
`?sldsk`/`?sctrn` **devuelven** valor en `HL`.

### Donde vive su estado

En `$F880-$F8A7`, sobre los glifos de los codigos 16-20 de la tabla de
fuentes -- la "reserva" del banco 7 que teniamos apuntada. `genfont.py`
emite ahora desde el codigo 32 (`FIRST`). Reparto actual de ese hueco:

| Rango | Uso |
|---|---|
| `$F800-$F87F` | `@bnkbf` (glifos 0-15) |
| `$F880-$F8A7` | estado y pila de `biosw` (glifos 16-20) |
| `$F8A6-$F8B1` | `bank$exit` (glifos 21-22) |
| `$F8B2-$F8BF` | variables de `?xmove`/`?move` (glifo 23) |
| `$F8C0-$F8FF` | `lstack`, la pila de la BDOS (glifos 24-31) |
| `$F900-$FFFF` | fuente real, codigos 32-255 |

### Y un solapamiento silencioso corregido de paso

La guarda de `bank.z80` rellenaba hasta `$F800`, pero `dfctbl`/`xdfctbl`
(RESBDOS.ASM) estan en `$F7B8`: **se solapaban**. Funcionaba solo porque
`RESBDOS.ASM` se ensambla despues y sus bytes ganaban. Ajustada a
`ds 0F7B8h-$`. Tercera vez que aparece el mismo patron -- dos `org` que
se pisan no dan ningun error.


---

## El `$` de DRI: un stub que suplantaba a la funcion 152

Sintoma: con el prompt funcionando, **ninguna orden se reconocia**
(`dir` -> `dir?`, `e:` -> `?`). El buffer de consola llegaba
**correcto** (`80 03 64 69 72 00` = longitud 3, "dir", terminado), asi
que la BDOS no tenia la culpa.

Cuatro breakpoints en los puntos de decision de la CCP lo acotaron:

| Punto | |
|---|---|
| `uc` (`$06B2`, conversion a mayusculas) | si para |
| `ccpbuiltin` (`$026D`) | **nunca** |
| `ccpdisk0` (`$029C`) | **nunca** |
| `perror` (`$098E`) | si para |

Y el volcado del FCB en `perror` dio el dato: `$0B02` = `00 00 FF FF FF
...`. Usuario y unidad a cero (bien) pero **el nombre y el tipo sin
tocar**. La funcion 152 (parse filename) no escribia nada, y con el tipo
a `$FF` la CCP se iba por `ccpdisk2`, que no pasa por ninguno de los dos
breakpoints del medio.

**La causa.** En el fuente original de DRI:

```
linea 236:  cpi 98!   jc  badfunc     <- sin $
linea 237:  cpi nxdf! jnc badfunc     <- sin $
linea 339:  bad$func:                  <- con $
```

En los ensambladores de DRI (MAC/RMAC) **el `$` dentro de un identificador
se ignora**: es solo un separador de legibilidad. Para DRI `badfunc` y
`bad$func` son **el mismo simbolo**. `zmac` los trata como distintos, asi
que `badfunc` quedaba indefinido -- y en una sesion anterior se "arreglo"
anadiendo un stub que devolvia `$FF`.

Ese stub **suplantaba al manejador real**, que es justo el que trata la
funcion 152:

```
bad$func:
	cpi 152
	jz parse
```

Corregido: los saltos apuntan a `bad$func` y el stub fuera.

### Auditoria: no hay mas casos

Como el patron puede repetirse, se audito todo (`scratchpad/dollar.py`):
buscar simbolos escritos de dos formas que solo varian en los `$`.

Salen 40 grupos, pero **ninguno es un bug**:

- **31** son parejas limpias "etiqueta + alias `equ`" (`out$delim equ
  outdelim`...). Mismo valor, dos nombres: correcto.
- **6** mas son alias explicitos del mismo tipo.
- **Los 3 restantes** (`conmode`, `qflag`, `parsepw`...) aparecen en
  `CCP3.ASM`, que **se ensambla por separado** -- solo su binario entra
  en `system.z80` via `ccp_image.z80`. No comparten espacio de nombres, y
  ademas los valores coinciden por los dos caminos (`conmode` es `$E0CF`
  tanto como `scb$pg+0cfh` en BDOS.ASM como `pag$off+033h` en CCP3.ASM).

`badfunc` era el unico caso donde, en vez de un alias, se habia anadido
codigo propio.

**Lección**: al portar fuente de DRI a un ensamblador moderno, un simbolo
"indefinido" que solo se diferencia por los `$` NO se resuelve escribiendo
una implementacion -- se resuelve con un alias, porque la implementacion
ya existe con la otra grafia. Un stub ahi no falla: **suplanta**, que es
mucho peor.

## La regla que faltaba: quien cambia de banco tiene que sobrevivir al cambio

Al empezar con el disco aparecio, de golpe, la misma equivocacion en tres
sitios distintos. Es la misma familia que el bug 4, pero al reves: alli el
problema era codigo que estaba duplicado **sin querer**; aqui es codigo que
**tenia** que estarlo y no lo estaba.

El patron equivocado, tal cual estaba escrito en `diskio.z80`:

```
            ld   a,(@dbnk)
            call ?bank
            ld   hl,@bnkbf
            ld   de,(@dma)
            ld   bc,128
            ldir
            ld   a,(@cbnk)
            call ?bank
```

Parece inofensivo y es letal. `diskio.z80` se ensambla en `$8000+`, o sea
en memoria **bancada**. En cuanto `?bank` selecciona el banco de usuario,
todo `$8000-$DFFF` cambia bajo los pies del programa: `?bank` vuelve
correctamente -- vive en la zona duplicada -- pero salta a una direccion
`$80xx` que en el banco de usuario es TPA vacia. De ahi el deslizamiento
por NOPs hasta el relleno de `$76` de la pagina cero que se veia en la
traza al arrancar con `A.IMG` presente.

Y lo mismo con las **variables**: `?move` guardaba `mv$de`/`mv$hl`/`mv$cnt`
en `move.z80`, tambien bancado, y las releia despues de cambiar de banco.
Leia la copia del otro contexto, que ahi no es ni siquiera una copia: es
TPA.

La regla, enunciada de una vez:

> **Todo lo que se ejecuta o se lee a los dos lados de un cambio de banco
> tiene que vivir en memoria que exista a los dos lados**: banco 7 (comun,
> una sola copia) o la zona duplicada `$7E00-$7FFF` (dos copias identicas,
> congeladas en el arranque por `dup_switcher`). Codigo puede ir en
> cualquiera de las dos. **Variables, solo en banco 7** -- en la zona
> duplicada hay dos copias y se escribiria una para leer la otra, que es
> exactamente el bug 4.

Lo que se hizo:

| Que | Estaba en | Pasa a |
|---|---|---|
| el `LDIR` de sector entre `@bnkbf` y `(@dma)` | repetido 4 veces en `diskio.z80` (bancado) | `xfer$out`/`xfer$in`, zona duplicada |
| el cuerpo de `?move` | `move.z80` (bancado) | zona duplicada |
| `xmv$dbnk`/`xmv$sbnk`/`mv$de`/`mv$hl`/`mv$cnt`/`mv$len` | `move.z80` (bancado) | banco 7, `$F8B2` |

`@cbnk` no hizo falta moverlo: DRI ya lo tiene en el `dseg` residente
(`$E064`), precisamente por esto -- hay que poder releerlo con el otro
banco puesto para saber a cual volver. `@dma` y `@dbnk` no (`$610C`/`$610F`),
asi que se leen **antes** de tocar el paginado.

`?xmove` si puede quedarse donde estaba: no conmuta nada, solo memoriza.

### De paso, dos cosas mas

`?move` tenia los dos punteros de la fase 1 cambiados: con `HL=@bnkbf` y
`DE=origen`, el `LDIR` copia `(HL)->(DE)`, o sea `@bnkbf` **encima del
origen**. Nunca habia saltado porque a ese camino solo se llega con un
XMOVE pendiente, y XMOVE solo lo usa la E/S de disco -- que hasta ahora no
habia llegado a ejecutarse.

Y `mov$bank` ya no necesita `xor a / call ?bank` antes del `jmp ?move`:
ahora `?move` esta en la zona duplicada y gestiona el mismo sus cambios de
banco.

**Leccion**: la pregunta antes de escribir `call ?bank` no es "¿estan los
datos donde toca?" sino "¿donde estare yo mismo cuando esto vuelva?".

## Los tres campos del DPH que GENSYS rellena y nosotros no

Arreglado lo de los bancos, la traza llego mucho mas lejos: `sd_login`
abre `A.IMG` y devuelve handle 0, la BDOS empieza a leer el directorio...
y se vuelve a colgar. Pero ya con un rastro legible:

```
selectdisk  $9833  4A  LD C,D        BC=0076
...
seldsk      $6058  79  LD A,C        AF=7644
            $6060  017783  LD BC,@dtbl
            $6063  09      ADD HL,BC     HL=8463
            $6082  CD00B8  CALL ipchl
            $CD0D  00      NOP
            $CD0E  00      NOP           (...)
```

SELDSK llamado con la unidad **$76**. Y `$76` es nuestro relleno de HALT
de la pagina cero. Unas lineas antes estaba la confirmacion:

```
            $B4BC  2AF0B2  LD HL,(curbcba)   HL=7676
```

La BDOS estaba recorriendo la lista de *buffer control blocks* **desde la
direccion 0**. Los tres ultimos campos de cada DPH estaban a cero:

```
            defw dpb_sd, csv_a, alv_a, 0,0,0
```

En CP/M 3, un 0 ahi no significa "no lo uses". Significa "usalo, esta en
la direccion 0". Es trabajo de GENSYS, igual que `?ERJMP` y la direccion
del SCB, y por el mismo motivo no estaba hecho.

| Campo | Estaba | Debe ser | Por que |
|---|---|---|---|
| DIRBCB | 0 | `dirbcbh` | La BDOS lee todo el directorio por aqui. Hace falta de verdad |
| DTABCB | 0 | `$FFFF` | `PSH=PSM=0`: el sector fisico ya son los 128 B del registro logico, no hay deblocking |
| HASH | 0 | `$FFFF` | Sin hash de directorio |

### La trampa de HASH

`$FFFF` y no `0`, y esta es la menos evidente de las tres. `test$hash`
(BDOS.ASM 9010) es:

```
test$hash:  lhld hash$tbla
            mov  a,l
            ora  h
            inr  a
            ret
```

Da `Z` ("no hay tabla") **solo** con `$FFFF`. Con `0` da `NZ`, o sea "si
hay tabla, en la direccion 0" -- y efectivamente en la traza se veia
`init$hash` ejecutandose de verdad y escribiendo alli con `move$out`.
El comentario de DRI en el llamante lo dice sin ambiguedad: *"is hashtbla
~= 0ffffh"*.

### La indireccion que solo existe en banked

DIRBCB **no** apunta al primer BCB: apunta a una **palabra** que contiene
la direccion del primer BCB. En BDOS.ASM se ve siempre bajo `[if BANKED]`:

```
            lhld dirbcba
            mov  e,m
            inx  h
            mov  d,m
            xchg
```

Un nivel de puntero mas que en el CP/M 3 no bancado. `DTABCB = $FFFF` se
comprueba **antes** de esa indireccion (`mov a,l / ana h / inr a / rz`),
asi que ahi el valor directo sigue valiendo.

`HASH` no lleva indireccion: es la direccion de la tabla y el byte
siguiente (HBANK) su banco.

### Formato del BCB

BDOS.ASM 8155, 15 bytes en sistemas bancados:

| Off | Campo | Inicial |
|---|---|---|
| 0 | DRV | `$FF` (libre) |
| 1-3 | REC | 0 |
| 4 | PEND | 0 |
| 5 | SEQ | 0 |
| 6-7 | TRACK | 0 |
| 8-9 | SECTOR | 0 |
| 10-11 | BUFFAD | el buffer de 128 B |
| 12 | BANK | 0 (sistema) |
| 13-14 | LINK | siguiente BCB, 0 = fin |

`DRV = $FF` es lo que marca el BCB como libre: la BDOS lo comprueba con
`mov a,m / inr a / jz`.

Se han puesto **dos** BCB compartidos por las cinco unidades -- el campo
DRV dice de quien es cada uno en cada momento. Con uno solo tambien
funcionaria; dos dan algo de cache al recorrer el directorio. Los buffers
viven en el banco de sistema, de ahi `BANK=0`.

**Leccion**: en las estructuras de CP/M 3, "sin usar" casi nunca se
escribe con un cero. Los centinelas son `$FFFF`, y un cero es una
direccion perfectamente valida que la BDOS va a usar tal cual.

## "No File" con un disco que la 2.2 si leia: OFF

El formato de disco lo define el DPB, no el driver, asi que un disco de
la 2.2 tiene que servir tal cual. Y sirve -- pero nuestro DPB no era el
mismo. Comparado campo a campo con `bios.z80` de `CPM_SD81`:

| Campo | 2.2 | CP/M 3 |
|---|---|---|
| SPT | 26 | 26 |
| BSH/BLM/EXM | 3 / 7 / 0 | 3 / 7 / 0 |
| DSM | 242 | 242 |
| DRM | 63 | 63 |
| AL0/AL1 | `$C0` / 0 | `$C0` / 0 |
| CKS | 16 | 16 |
| **OFF** | **2** | **0** |

`OFF` son las pistas de sistema reservadas al principio del medio. Con
`OFF=0` la BDOS buscaba el directorio en la pista 0 -- las pistas de
arranque -- no encontraba ninguna entrada valida y `DIR` contestaba "No
File". Ni error de E/S ni cuelgue: el disco se leia perfectamente, solo
que por el sitio equivocado.

`dpb_ram` (disco RAM) se queda con `OFF=0`, que es lo correcto: no tiene
pistas de arranque.

## El color no se veia: falta encender el Chroma

Los atributos estaban bien calculados y bien escritos, pero la salida de
video seguia siendo monocroma. El registro de modo Chroma (`$7FEF`) valia
`$0F`, y hacen falta sus dos bits altos:

| Bit | Nombre | Por que |
|---|---|---|
| 5 | `color_enable` | Saca RGB en vez de luminancia: `VRED = color_enable? cred&ncsync : video&ncsync` (SD81.v:1600-1603) |
| 4 | `color_mode` | Toma el atributo de `attr_addr_m1`, o sea de `ATTR_OVR` -- justo lo que programa `?init`. Con 0 leeria `attr_addr_m0`, otra direccion (SD81.v:1151/1165/1535) |
| 3-0 | color del borde | Se deja el `$F` que ya habia |

O sea `$3F`. Y la decodificacion es de **16 bits** (`Addr==16'h7FEF`,
SD81.v:427), asi que hay que escribirlo con `out (c),a` y BC entero, no
con el `out (n),a` que usamos para el paginado -- ese pone A en el byte
alto de la direccion, no B.

Merece la pena quedarse con la forma del fallo: el atributo llegaba a la
memoria de video correcto, el hardware lo leia correcto, y aun asi no se
veia nada. Cuando algo "no tiene efecto" sin dar error, el sospechoso
suele ser un bit de habilitacion, no el dato.

## Los .COM no arrancaban: no habia cargador

Al teclear el nombre de un programa no pasaba nada. Ni error, ni cuelgue:
volvia el prompt. Dos problemas encadenados.

### 1. `bdosbase` sin poner

Otro campo de GENSYS que estaba a cero, y la CCP lo usa para dos cosas
distintas al lanzar un transitorio (`xcom`):

```
	lhld	realdos-1	;put fcb in the loader's stack
	dcr	h		;page below LOADER (or bottom RSX)
	mvi	l,0C0h
...
	lhld	realdos-1	;base page of BDOS
	xra	a
	mov	l,a
	sphl			;top of stack below BDOS
```

Con el campo a cero, `realdos`=0 y `dcr h` da `$FF`: el FCB se copiaba a
**`$FFC0`**, encima de la tabla de fuentes en el banco comun, y el SP
quedaba en **`$0000`**, asi que el primer `push` escribia en `$FFFE`.
Toda la pila del transitorio caia en memoria comun.

Ahora apunta a `LDR_BASE` (`$DF00`): FCB en `$DEC0` y pila bajando desde
`$DF00`, las dos dentro del TPA del banco de usuario -- la colocacion que
describe el propio comentario de DRI.

### 2. La funcion 59 no existia

La CCP termina toda ejecucion externa asi:

```
loader:	mvi	c,loadf		;use load RSX to load file
	jmp	bdos
```

`loadf` es la **funcion 59 (P_LOAD)**, y la BDOS **no la implementa**: en
CP/M 3 la aporta `LOADER.RSX`. Nosotros quitamos `LOADER3.ASM` hace
tiempo -- ni siquiera esta en `dri_src/` -- asi que 59 caia en
`bad$func` de RESBDOS.ASM (queda entre `ndf`=51 y 98), que devuelve
`A=$FF` y poco mas. Y como el `jmp bdos` es un salto de cola, el `ret` de
la BDOS recogia el `$0100` que `xcom8` habia apilado y saltaba a un TPA
vacio.

De ahi el sintoma tan silencioso: la CCP hacia su parte entera y
correctamente, y lo que faltaba era la pieza que ni siquiera es de la
BDOS.

### La solucion: `loader.z80`

Un stub de 256 bytes en `$DF00` del banco de **usuario**, que es el
mecanismo de RSX de DRI reducido a su minima expresion:

```
ldr$entry:  ld   a,c
            cp   59
            jp   nz, call5_entry     ; el resto de funciones, tal cual
```

`$0005` salta aqui (via `@MXTPA`, que `set$jumps` copia a `$0006`), o sea
que el stub es el primer eslabon de la cadena BDOS: atiende la 59 y pasa
todo lo demas a `call5_entry`. La 59 abre el FCB que le deja la CCP en
DE, lee registros de 128 B desde la direccion que viene en FCB+33
(normalmente `$0100`) y vuelve; el `ret` recoge el `$0100` de la CCP y
entra en el programa.

Tiene que vivir arriba del TPA por dos razones **distintas**:

1. Un `call 5` desde un programa llega con el banco de usuario puesto, asi
   que el destino tiene que existir en ese banco.
2. El programa se carga en `$0100` y crece: un cargador en el TPA bajo
   seria machacado por lo que esta cargando.

Y no hay reubicacion que hacer: se ensambla **en su direccion de
ejecucion**, asi que la imagen plana lo deja en `$DF00` del banco de
sistema y `ldccp_real` lo copia a `$DF00` del banco de usuario -- misma
direccion logica, banco distinto. Se recopia en cada arranque en
caliente, junto con la CCP.

De paso, `@MXTPA` vuelve a significar lo que dice su nombre. En un CP/M+
real, "techo del TPA" y "entrada de la cadena BDOS" son la misma
direccion; aqui habian divergido porque `call5_entry` vive en el banco 7.
Ahora las dos son `LDR_BASE`.

Coste: 256 bytes de TPA (de 56K a 55.75K).

## `?stbnk` destruia su propio argumento

Con el cargador ya puesto, la traza decia que todo iba bien: el `open`
funcionaba, el bucle leia muchos sectores, `ldr$dma` avanzaba desde
`$0100` y se llegaba limpiamente a `ldr$done`. Y aun asi, al `ret`
volvia el prompt sin haber ejecutado nada.

El culpable estaba en la tabla de saltos del BIOS:

```
?stbnk:     xor  a
            call bnksel
            jmp  setbnk
```

SETBNK (funcion 28 del BIOS) recibe en **A** el banco donde esta el DMA.
Pero el `xor a` que hace falta para pasar a sistema **destruye ese
argumento**, y como `?bank` preserva AF, lo que llega a `setbnk` (`sta
@dbnk`, BIOSKRNL.ASM) es el cero, no lo que paso el llamante. `@dbnk`
valia siempre 0: "el DMA esta en el banco de sistema".

La cadena completa: al cargar un `.COM`, la BDOS hace `mvi a,1 / call
setbnkf` (BDOS.ASM:5142) para decir que el buffer esta en el banco de
**usuario**. Llegaba un 0. `xfer$out` veia `@dbnk == @cbnk == 0`, se
ahorraba el cambio de banco -- correctamente, segun la informacion que
tenia -- y los 128 bytes de cada sector acababan en `$0100` del banco de
**sistema**. En el de usuario seguia la CCP intacta, asi que el `ret` del
cargador la reiniciaba: prompt de vuelta y "no ha pasado nada".

### Por que tardo tanto en dar la cara

Porque los buffers de directorio viven en el banco de sistema (`BANK=0`
en el BCB, `drvtbl.z80`). Para ellos, el 0 equivocado **era el valor
correcto**, por casualidad. Todo el trabajo de disco que habiamos
probado hasta ahora -- el `DIR`, el login, la lectura del directorio --
pasaba por ese camino y funcionaba. El primer uso real de `@dbnk` con
valor distinto de cero fue justo la carga de un transitorio.

El arreglo es guardar el argumento en un registro que sobreviva:

```
?stbnk:     ld   b,a
            xor  a
            call bnksel
            ld   a,b
            jmp  setbnk
```

`B` vale porque `?bank` hace push/pop de BC.

**Leccion**: las entradas de esa tabla que llevan `xor a` delante solo
son correctas si la rutina de destino no recibe nada en A. Revisadas
todas: `?tim`/`?ldccp`/`?rlccp` no reciben argumentos, `?bnksl` pasa A
tal cual sin tocarlo, `?xmov` usa B y C (que `?bank` preserva) y las diez
entradas de E/S de caracter usan C. `?stbnk` era la unica que pasaba algo
en A -- y la unica rota.

## MOUNT: por que no montaba nada (y por que era peor que eso)

`mount.asm` de la 2.2 parchea directamente el array de handles del BIOS:

```
DISKHANDLE  equ 0E018h          ; VARBASE($E000)+24: handles de A-D
```

En CP/M 3 eso esta mal por partida doble.

**Primero, la direccion.** Nuestro `disk_handle` estaba en `$811F`, o sea
en el banco de SISTEMA -- que un programa de usuario no puede ni ver. Y
`$E018` en nuestro mapa cae dentro de los datos de la BDOS residente, en
la zona comun: escribir ahi no solo no montaba nada, ademas **corrompia
el sistema**.

**Segundo, aunque acertara la direccion, tampoco habria servido.** En la
2.2, `bios.z80` abre los cuatro `.IMG` una sola vez en el arranque en
frio y no vuelve a tocar `disk_handle` -- por eso el parche se quedaba
puesto. Nuestro `sd_login` reabria en cada login, y MOUNT termina
haciendo un reset de unidad (BDOS 37) justo para que la BDOS relea el
directorio... o sea, provocando el proximo login. El handle recien
montado duraba lo que tardaba en ejecutarse la siguiente instruccion.

### Los dos cambios

**`disk_handle` se muda al banco comun**, a `$F8FC` (`DISKHANDLE` en
`memmap.inc`). Va justo detras de `lstack`, en la reserva de la tabla de
fuentes: `lstack` es el TOPE de una pila que crece hacia abajo, asi que
en `$F8FC` y siguientes no se escribe nunca. Arranca a `$FF,$FF,$FF,$FF`
desde la propia imagen, y como la imagen se carga una sola vez, **un
montaje sobrevive al arranque en caliente**.

**`sd_login` solo abre si el handle vale `$FF`.** Ese es ahora el
significado de "sin abrir", y es lo que permite que MOUNT deje el suyo y
nadie se lo pise.

### `mount3.asm`

Copia del original con `DISKHANDLE equ 0F8FCh`. El fuente de la 2.2
(`CPM_SD81/mount.asm`) se queda intacto. Se ensambla con
`build_mount3.bat` y produce `MOUNT3.COM`.

El protocolo con el MCU no cambia ni una linea: son `in`/`out`, y esos
funcionan desde cualquier banco.

**Leccion**: un programa de usuario que parchea estructuras del BIOS es
una dependencia invisible. En la 2.2 no habia bancos y una direccion era
una direccion; aqui, "esta en `$E018`" dejo de querer decir nada sin
decir tambien "en que banco". Cualquier otra utilidad que hicieramos
para la 2.2 con este patron hay que revisarla igual.

## La tabla de saltos del BIOS no tenia 3 bytes por entrada

Turbo Pascal 3.0 cargaba entero -- 30.848 bytes, `ldr$dma` = `$7980` al
salir del cargador -- hacia **una sola** llamada a la BDOS (la 25, "cual
es la unidad actual") y no volvia a llamar nunca mas. Se quedaba dando
vueltas en `scan_keys` sin haber escrito un caracter en pantalla.

Y `PIP` y `ED` funcionaban perfectamente. Esa era la pista: los dos
hacen toda su E/S por la BDOS. Turbo Pascal no.

### El problema

Un programa de CP/M 2.2 llama al BIOS sin pasar por la BDOS. Lee la
palabra de `$0001`, le resta 3 para obtener la base del BIOS, y de ahi
indexa **de tres en tres**: `CONST=base+6`, `CONIN=base+9`,
`CONOUT=base+12`...

Nuestra tabla real (`bank.z80`) no cumple eso, porque lleva el cambio de
banco metido dentro de cada entrada:

| Entrada | Direccion | Tamano |
|---|---|---|
| `?boot` | `$7E6C` | 3 |
| `?wboot` | `$7E6F` | 7 (`xor a / call bnksel / jmp wboot`) |
| `?const` | `$7E76` | 6 (`ld hl,const / jmp biosw`) |
| `?conin` | `$7E7C` | 6 |
| `?cono` | `$7E82` | ... |

Con `$0001` = `?wboot` = `$7E6F`, el programa calcula base = `$7E6C` y
pide CONOUT en `$7E78`... que cae **a medias de la instruccion `ld
hl,const`** de `?const`.

### La solucion

Una tabla intermedia, `bios$tbl`, de 33 `jp` de 3 bytes que apuntan a las
entradas de verdad, y `set$jumps` poniendo `BIOSTBL+3` en `$0001` en vez
de `?wboot`.

Vive en `$DF80`, la segunda mitad de la pagina del cargador, por los
mismos dos motivos que el cargador: esta en el banco de usuario (que es
donde corre quien la llama) y `@MXTPA` la protege de que la machaque el
propio programa. Los destinos (`$7Exx`) son alcanzables porque la zona
duplicada existe en los dos bancos.

Las dos cosas que viven en `$0001` conviven sin problema con la
indireccion: `jmp 0` salta a `BIOSTBL+3`, que es `jp ?wboot`.

Coste: un `jp` de mas por llamada al BIOS. La BDOS no pasa por aqui --
usa los simbolos `?xxx` directamente.

**Leccion**: meter logica dentro de una tabla de saltos rompe el
contrato de la tabla. El espaciado ERA parte del interfaz, aunque en
ningun sitio estuviera escrito, y ningun ensamblado lo iba a detectar.
Lo unico que lo delataba era un programa que usara el interfaz de
verdad -- y para eso hacia falta que primero funcionara la carga de
transitorios.

## La zona duplicada estaba dentro del TPA

Turbo Pascal arranca, imprime su rotulo, pregunta por los mensajes de
error, contesta que si, empieza a cargar `TURBO.MSG`... y se para. Con
`N` (sin mensajes) funciona perfectamente.

La traza lo enseno sin ambiguedad:

```
$035F  LD HL,($0001)      HL=DF83      ; base del BIOS
$0362  ADD HL,DE          DE=0009 -> HL=DF8C
$0363  JP (HL)
$DF8C  JP $7E82                        ; CONOUT, correcto
$7E82  LD HL,$F60E                     ; ld hl,conout   correcto
$7E85  JP $7E3F                        ; jmp biosw      correcto
$7E3F  0D        DEC C                 ; <-- BASURA
$7E40  0A        LD A,(BC)
$7E41  34        INC (HL)
```

Los bytes que se ejecutan en `$7E3F` son `0D 0A 34 31 55 6E 6B 6E 6F 77
6E 06 0F 20 73`, o sea **`..41Unknown.. s`**: texto de `TURBO.MSG`,
literal.

La zona duplicada del conmutador vivia en `$7E00-$7FFF`, **en mitad del
TPA**, y nada la protegia. `dup_switcher` la copia al banco de usuario en
el arranque, pero `@MXTPA` decia `$DF00`, asi que para cualquier programa
esos 512 bytes eran memoria libre. `TURBO.COM` ocupa hasta `$797F` y
carga los mensajes justo encima, pasando por `$7E00`.

Lo mismo explicaba que la pantalla se llenara de basura al editar un
`.PAS`: el buffer del editor crece hacia arriba y arrasa lo mismo.

### Por que tardo tanto en aparecer

Porque ningun programa habia llegado tan arriba. `PIP`, `ED`, `DIR`,
`STAT` y compania son todos pequenos. Hizo falta un `.COM` de 30 KB que
ademas cargara datos encima de si mismo.

### La mudanza

| Zona | Antes | Ahora |
|---|---|---|
| Cargador + `bios$tbl` | `$DF00-$DFFF` | `$DD00-$DDFF` |
| Zona duplicada | `$7E00-$7FFF` | `$DE00-$DFFF` |
| `@MXTPA` / `bdosbase` | `$DF00` | `$DD00` |
| TPA | `$0100-$DEFF`, con una mina en `$7E00` | `$0100-$DCFF`, entero |

El cargador queda **debajo** de la zona duplicada, y no al reves. `$0006`
es a la vez la entrada a la BDOS y el techo del TPA que leen los
programas, asi que todo lo que haya que proteger tiene que estar por
encima de `LDR_BASE`. Con el orden invertido, la zona duplicada volveria
a caer dentro de lo que un programa cree libre.

El TPA pasa de 55,5K a 55K. En la practica se gana: esos 512 bytes ya
eran inutilizables, solo que en vez de dar un error corrompian el
sistema.

### El efecto secundario: `WINBLK`

La zona duplicada pasa del bloque 3 al bloque 6, y el 6 era `WINBLK`, la
ventana temporal de `map1blk` (disco RAM y relleno de HALT de la pagina
cero). `map1blk` vive DENTRO de la zona duplicada, asi que no puede estar
en el bloque que esta reprogramando. Tampoco vale el 4, donde esta el
driver. `WINBLK` pasa al 3, que queda libre justo con esta mudanza.

Conviene tener clara la diferencia, porque son cosas distintas:

- **La zona duplicada RESIDE.** Ocupa direcciones de verdad, siempre.
- **`WINBLK` no reside**: se reprograma el mapeo, se copian 128 bytes y
  se deja como estaba, todo dentro de una misma llamada al BIOS y con el
  banco de sistema puesto. No se pierde un byte de nadie. Su unico
  requisito es que no se ejecute nada desde ese bloque mientras la
  ventana esta abierta.

**Leccion**: `@MXTPA` no es documentacion, es una promesa. Todo lo que
resida por debajo de esa direccion y no sea del programa es una mina, y
no salta hasta que aparece un programa lo bastante grande. La pregunta
que habria que haberse hecho al crear la zona duplicada no era "¿donde
cabe?" sino "¿de quien es esta memoria?".

### Y una consecuencia inmediata: `mc45_ext67`

Nada mas mudar la zona duplicada al bloque 6, el `RAND USR` volvia a
BASIC sin mas. La causa estaba en el orden de habilitacion de MC45.

`start:` (system.z80) enciende MC45 para poder ejecutar por encima de
`$8000` -- pero eso solo cubre los bloques **4 y 5** (`$8000-$BFFF`). El
6 y el 7 necesitan `mc45_ext67` (registro 2062), que se activaba dentro
de `?init`.

Con `?boot` en `$7E6C` daba igual: el bloque 3 esta por debajo de
`$8000` y siempre es ejecutable. Con `?boot` en `$DE6C` es imposible: el
`jp ?boot` necesita que el bloque 6 ya sea ejecutable, y a `?init` solo
se llega pasando por `?boot`.

`mc45_ext67` pasa por tanto a `start:`, justo detras del MC45 ON. La
escritura vale ahi porque la ventana MMIO sigue abierta -- la cierra
`?init` mucho despues, con `ld (2056),a`.

Merece la pena fijarse en la forma del fallo: **ninguna guarda de
ensamblado podia cogerlo**. El binario era correcto byte a byte; lo que
cambio fue en que momento esa memoria se puede ejecutar. Lo unico que lo
delataba era mirar en el `.lst` a donde habia ido a parar `?boot`.

## Dos `org` solapados, otra vez -- y la herramienta que faltaba

Al mudar la zona duplicada, `start:` (system.z80) crecio 5 bytes: los que
ocupa activar `mc45_ext67` ahi. Eso desplazo todo BIOSKRNL 5 bytes hacia
abajo, el bucle de inicializacion de unidades de `boot:` acabo en `$605C`
y se solapo con `seldsk`, que tenia delante un **`org 06058h` literal**.

El sintoma: `jnz d$init$loop` saltaba a `$3279` y de ahi a un `RST 38` y
un `HALT`.

Lo interesante es lo que costo verlo. El `.lst` decia:

```
6057  C23560    jnz d$init$loop
605A  C398F5    jmp boot$1
```

...y el `.bin` tenia `C2 79 32 06 61 69`, que son los primeros bytes de
`seldsk`. Listado y binario **no coincidian**, y ni el ensamblador ni las
guardas `ds <siguiente>-$` podian avisar: esas solo cogen desbordamientos
hacia adelante, no un `org` clavado a una direccion que se quedo corta.

Se persiguio primero como corrupcion en memoria, con un breakpoint de
escritura en `$6058`. Las dos escrituras que salieron eran legitimas (el
cargador metiendo la imagen, y el `LDIR` del relleno de HALT escribiendo
en la pagina 0 a traves de la ventana -- el breakpoint vigila direcciones
logicas, no paginas). Lo que lo resolvio fue mirar el `.bin` directamente
y ver que el byte malo **ya venia en el fichero**.

### El arreglo

El `org 06058h` era una direccion calculada a mano: "lo que le habria
tocado a este bloque si no hubieramos insertado el `org` del banco 7".
Pasa a ser el idioma que ya usabamos en `init.z80` y `bank.z80`:

```
bioskrnl$cseg$save equ $
	org 0F598h
	... bloque del banco 7 ...
	ds 0F704h-$
	org bioskrnl$cseg$save
```

Sin numeros magicos, y crezca lo que crezca lo de delante.

### `checkimg.py`

Compara el `.lst` con el `.bin` y avisa de cada byte que no coincide.
`build_system.bat` lo ejecuta despues de cada ensamblado y falla si hay
discrepancias.

Es la unica red que cubre este fallo: **la guarda `ds` detecta que un
bloque se pasa de largo; esto detecta que otro bloque le cae encima.**
Son dos mitades del mismo problema y solo teniamos una.

## Formato de disco nuevo: 2 MB

El formato heredado del 2.2 (IBM 3740 de 8": 26 sectores, 250 KB, 64
entradas de directorio) se quedaba corto. Conviene tener claro que **no
hay disquete**: el disco es un fichero en la SD al que se accede por
desplazamiento de bytes,

```
sd_off = (trk*SPT + sect) * 128
```

...y el MCU hace `fseek` ahi. No hay pistas, ni cabezas, ni sectores
fisicos. La geometria es enteramente nuestra y se elige por conveniencia,
no por imitar un formato que no existe.

### Lo que de verdad limita

| Limite | Valor |
|---|---|
| `compute_offset` | 24 bits -> 16 MB por unidad |
| Fichero CP/M 3 | 32 MB |
| `fread`/`fwrite` del MCU | **512 bytes** (`BUFFSIZE`, GLOBALS.h:37) |
| Manejadores de fichero | **4** (`h<4`, COMMANDS.cpp) -- justo A-D |
| Buffers ALV | `(DSM/4)+2` por unidad, en el banco de sistema |
| Barrido de directorio | Cada operacion lo lee entero, a `fseek`+`fread` por registro |

El ultimo es el que manda y es facil pasarlo por alto: **el tamano del
directorio se paga en cada operacion de fichero**, no solo al listar. Por
eso 256 entradas y no 512.

Sobre el limite de 512: el firmware es defensivo en lectura
(`count<=BUFFSIZE`, si no devuelve ceros y `status=0x01`), pero
`cmd_f_write` **no comprueba nada** y copia `count` bytes -- de 16 bits --
en un buffer de 512. Si algun dia se hace deblocking de escritura, hay
que arreglar el firmware primero.

### El formato

| Campo | Antes | Ahora | Por que |
|---|---|---|---|
| SPT | 26 | 128 | Potencia de dos: `compute_offset` pasa a desplazamientos |
| BLS (BSH/BLM) | 1024 (3/7) | 2048 (4/15) | Mitad de entradas de asignacion |
| DSM | 242 | 1023 | 1024 bloques x 2K = 2 MB |
| DRM | 63 | 255 | 256 ficheros |
| AL0/AL1 | C0h/0 | F0h/0 | 4 bloques = 8 KB de directorio |
| EXM | 0 | 0 | BLS=2048 con DSM>255 |
| CKS | 16 | 8000h | Medio fijo |
| OFF | 2 | 0 | No arrancamos desde estas imagenes |

`CKS=8000h` (medio fijo, sin vector de checksum) es defendible porque **la
unica forma de cambiar una imagen es MOUNT3, que ya hace un reset de
unidad**. Nadie puede cambiarla a espaldas de CP/M. A cambio se ahorra el
checksumeo del directorio en cada operacion, que con este driver no es
poca cosa.

### Herramientas

- `mkblank.py` crea una imagen vacia (2 MB de `$E5`).
- `diskdefs` tiene las definiciones de cpmtools: `sd81-2m` para el formato
  nuevo y `sd81-250k` para leer las imagenes antiguas.

### La implementacion

| Fichero | Cambio |
|---|---|
| `drvtbl.z80` | `dpb_sd` con los valores nuevos; CSV de las 5 unidades a 0 |
| `diskio.z80` | `compute_offset` a desplazamientos; fuera CSV/ALV |
| `memmap.inc` | `ALV_BASE`/`ALV_SD`/`ALV_RAM` |
| `system.z80` | Reserva de los ALV detras de `ccp_image.z80`, con guardas |

`compute_offset` se simplifica mucho al ser SPT una potencia de dos:

```
            ld   hl,(@trk)
            ld   b,7
co_trk:     add  hl,hl               ; HL = trk*128
            djnz co_trk
            ld   de,(@sect)
            add  hl,de               ; HL = lba
            ld   d,0
            ld   b,7
co_shl:     add  hl,hl               ; DHL = lba*128
            rl   d
            djnz co_shl
```

`lba` cabe en 14 bits (trk y sect van de 0 a 127) y el desplazamiento
final da 21, que es lo que ocupan 2 MB. Antes SPT valia 26 y hacia falta
un bucle de multiplicar de 8 vueltas.

Los ALV pasan de 63 a **257 bytes por unidad** y ya no caben en el hueco
del XIOS, que tiene que acabar antes de `$8A00`. Se reservan detras de la
imagen de la CCP, con una guarda a cada lado: `ds ALV_BASE-$` falla si la
CCP crece de mas, y `ds LDR_BASE-$` si los buffers llegaran al cargador.
Direcciones por constante, nunca literales -- que es justo lo que fallo
con el `org 06058h`.

## `DIR fichero [FULL]` daba tamanos inventados: el DPB en el banco equivocado

Sintomas: `PIP.COM` (10 KB reales, 5 bloques) salia como **20K**;
`HELP.HLP` (76 KB, 38 bloques) como **152K**; y "Used/Max Dir Entries"
como **`44/H942`**.

El disco estaba perfecto -- leyendo `A.IMG` desde el anfitrion,
`PIP.COM` son 68 registros en 5 bloques y `HELP.HLP` 599 en 38, y las 44
entradas usadas coinciden con lo que dice `DIR`.

La pista era la `H` de `H942`. Un parametro mal puesto da un numero
equivocado; **un valor no numerico dice que la estructura entera es
basura**.

### La causa

La funcion 31 de la BDOS (*get disk parameter address*) devuelve al
programa la direccion del DPB **tal cual**. Nuestro `dpb_sd` estaba en
`$8202`, o sea en el banco de SISTEMA. El programa corre en el banco de
USUARIO, dereferencia `$8202` y lee TPA.

Y el comentario que encabezaba `drvtbl.z80` decia justo lo contrario:

> Zona de datos pura (ningun XDPH/DPB se ejecuta como codigo), asi que no
> hay problema de MC45 ni de duplicacion -- puede vivir en banco comun o
> en sistema indistintamente.

Falso. Que no se ejecute no significa que no se lea desde el otro banco.
El razonamiento cubria la CPU y se olvidaba de los programas.

### El arreglo

Los dos DPB (17 bytes cada uno) se mudan a `$F775`, en el hueco que
rellenaba la guarda del bloque de banco 7 de `init.z80` -- 47 bytes que
estaban de puro relleno. Cero coste de TPA.

Son datos de **solo lectura**, asi que basta con que existan en una
direccion visible desde los dos bancos; no hace falta ni duplicacion ni
sincronizacion.

`init.z80` cierra ahora su guarda en `DPB_SD` en vez de en `$F7A4`, y
`drvtbl.z80` abre un parentesis con `org DPB_SD` y lo cierra con
`ds 0F7A4h-$` / `org drvtbl$save`.

### Lo que queda por mirar

La funcion 27 (*get allocation vector address*) tiene el mismo problema:
devuelve `ALV_BASE`, que esta en el banco de sistema. No se ha tocado
porque las utilidades de CP/M 3 piden el espacio libre con la funcion 46,
que devuelve el dato en el DMA y funciona. Pero un programa de CP/M 2.2
que use la 27 leera basura.

**Leccion**: en un sistema bancado, cualquier BDOS que devuelva un
PUNTERO obliga a preguntarse desde que banco lo va a leer quien lo
recibe. La lista es corta -- 27 y 31 -- y ahora esta revisada.

## Disco RAM (unidad E): el directorio

El driver (`ram_read`/`ram_write`/`rdx$setup`) llevaba escrito desde el
principio, sin probar. Lo que le faltaba no era memoria comun -- no gasta
ni un byte de banco 7 -- sino que el directorio existiera.

| Pieza | Donde |
|---|---|
| `ram_read`/`ram_write`/`rdx$setup` y sus variables | `diskio.z80`, banco de sistema |
| `map1blk`, `xfer$out`/`xfer$in` | zona duplicada |
| `dpb_ram` | comun, 17 B |
| `alv_e` | 14 B en `ALV_BASE`, banco de sistema |

Geometria: BLS=8192, o sea **un bloque = una pagina de 8 KB = una pista**
de 64 registros. DSM=48 son 49 bloques, las paginas 15-63 (`RAMDISK_BASE`
en adelante), 392 KB. El directorio es el bloque 0 = la pagina 15 entera:
256 entradas de 32 B = 8192 B justos, de ahi `AL0=80h`.

### Formatear sin borrar

`ram_init` se llama una sola vez por arranque en **frio**, desde el bucle
de unidades de `boot:`. El arranque en caliente no pasa por ahi (`wboot`
va directo a `boot$1`), asi que el contenido sobrevive a un Ctrl-C o al
final de un programa.

Pero ademas sobrevive a **recargar CP/M entero**: las paginas 15-63 no
las toca nadie al cargar el sistema, que va a las 3-7. Formatear a ciegas
en cada arranque borraria el disco RAM cada vez que se reinicia -- en un
ZX81, a menudo.

La deteccion no usa firmas ni metadatos: **se comprueba si el directorio
es un directorio**. El primer byte de cada entrada solo puede valer `$E5`
(libre), `$00-$0F` (numero de usuario), `$20` (etiqueta) o `$21` (sello
de tiempo). Cualquier otro valor en cualquiera de las 256 entradas
significa basura, y entonces se formatea.

Con RAM aleatoria cada byte tiene un ~7% de parecer valido, asi que los
256 a la vez son practicamente imposibles. Y no hay estado que mantener
sincronizado, que es lo que suele romperse en los esquemas con firma.

## Trampolin: la E/S de caracter sale del banco 7, entran los DPH

Para que `BIOS SELDSK` y `DRVTBL` sirvan de algo hacian falta 207 bytes
de banco comun, y solo quedaban 13. La reserva estaba escondida en un
sitio que llevaba tiempo delante de las narices.

### Una premisa que habia caducado

DRI pone la E/S de caracter en `cseg` (memoria comun) para que un
programa pueda llamar al BIOS **sin cambiar de banco**. Perfectamente
razonable... hasta que metimos `biosw` delante de cada entrada de la
tabla de saltos. El envoltorio ya selecciona sistema antes de saltar al
cuerpo y restaura el banco del llamante al volver.

O sea que el cuerpo de esas rutinas **llevaba tiempo sin necesitar ser
comun**. Solo lo parecia, porque el comentario de DRI seguia ahi.

Comprobados los dos caminos de entrada antes de moverlas:

- `?const`/`?conin`/`?cono`/`?list`/`?auxo`/`?auxi`/`?conos`/`?auxis`/
  `?auxos`/`?lists` pasan por `biosw`.
- `?dvtbl`/`?drtbl` hacen `xor a / call bnksel` antes del salto.
- Los alias de la BDOS (`conoutf equ ?cono`, `constf equ ?const`...)
  apuntan a la **tabla**, no al cuerpo.

Nadie llega ahi con el banco de usuario puesto.

### El reparto nuevo del bloque comun

| Se queda | Bytes |
|---|---|
| `boot$1`, `wboot` | 21 |
| `set$jumps` (selecciona usuario a mitad) | 33 |
| `boot$stack` | 56 |
| `bnksel` | 6 |

| Se va a `BKIOEXT` ($CC80, banco de sistema) | Bytes |
|---|---|
| `devtbl`, `getdrv` | 8 |
| `conout`, `auxout`, `list`, `const`, `conin`, `auxin` | 30 |
| `conost`, `auxost`, `listst`, `auxist` | 24 |
| los cuatro `*$scan` con sus `*$next` | 90 |
| `coster` + `xofflist` | 56 |
| `cist1`, `cost1`, `ci1`, `ci$rdy`, `not$q`, `not$s` | 40 |

**248 bytes recuperados.** `xofflist` estaba detras de `bnksel` en el
fuente de DRI y se trae con `coster`, que es quien lo usa, para que el
parentesis sea uno solo.

### Y el banco 7 queda asi

| Rango | Uso |
|---|---|
| `$F598-$F617` | `boot$1`, `wboot`, `set$jumps`, `boot$stack`, `bnksel` |
| `$F618-$F703` | **`@dtbl` + los 5 XDPH/DPH** (207 B) |
| `$F704-$F774` | `ldccp_real`, `ldc$copy`, `call5_entry` |
| `$F775-$F7A3` | los dos DPB |
| `$F7A4-` | variables de `?bank` |

Cuatro bloques consecutivos, cada uno con su guarda `ds <siguiente>-$`, y
ninguna direccion literal: `BKIOEXT`, `DTBLORG`, `DPBORG` y `LDR_BASE`
salen todas de `memmap.inc`.

### Por que el DPH no podia ir en la pagina del cargador

Porque **no es de solo lectura**. Lleva 9 bytes de scratch y el byte MF
que escribe la BDOS. La pagina del cargador esta "duplicada e identica"
(la imagen en sistema, la copia en usuario), lo cual basta para datos
inmutables como `@dtbl` o los DPB, pero no para algo que se escribe:
habria dos copias divergiendo. Por eso hubo que liberar banco 7 de
verdad en vez de aprovechar los 28 bytes libres de `$DDE4`.

### Lo que seguia roto, y ya no

La funcion 27 (*get allocation vector address*) devolvia `ALV_BASE`, que
estaba en el banco de sistema: una direccion correcta a la que el
programa que preguntaba no podia llegar. La excusa era que son 1042
bytes y "no caben en comun ni de lejos" -- cierto mientras el banco 7
estuvo lleno al 100%.

Dejo de serlo con el realineado DRI (`layout_dri.md`): al subir el BDOS
residente a `$F931` quedaron 1382 bytes contiguos libres en `$F032`, y
el ALV se mudo alli. No cuesta TPA -- el banco 7 es memoria comun -- y
de paso libera 1042 bytes del banco de sistema, que se los queda de
margen la imagen de la CCP (de 256 bytes a 1280).

A quien afecta: a utilidades de **CP/M 2.2** que recorren el mapa de
bits a mano, tipo `STAT`. Las de CP/M 3 usan la funcion 46 (*Get Disk
Free Space*), que devuelve el dato ya calculado -- por eso
`SHOW [SPACE]` funcionaba con la 27 rota.

## `ERASE.COM` escribia sobre la pagina cero: `searcha`

`ERASE B:X.COM` desde A: funcionaba; `A:ERASE X.COM` desde B: colgaba la
maquina. La diferencia no era la unidad: la primera forma usa el **ERASE
interno de la CCP** y la segunda carga **ERASE.COM** como transitorio.
Dos programas distintos.

La traza de llamadas a la BDOS (BP en `$DD00`, que las ve todas) dejo el
borrado fuera de sospecha:

```
$0F open  $3B P_LOAD  $0C $0C version  $6D $19 $20 $2D
$1A DMA   $11 F_SFIRST(DE=006C)   $31 x6 F_SCB
$0B       $1A         $13 F_DELETE   <- y VUELVE
$1A       $31 x7 F_SCB              <- y aqui se acaba
```

El `$13` vuelve, o sea que el fichero se borra bien. Lo que mata la
maquina viene despues:

```
$04D7  LD C,$47        ; offset $47 del SCB
$04D9  CALL $06F6      ; leer campo del SCB (funcion 49)
$04DC  LD ($0F3D),HL   ; HL = 0000
...
$061D  LD HL,($0F3D)   ; HL = 0000  -> destino
$0621  LD BC,$006C
$0625  LD A,(BC) / LD (DE),A / INC BC / INC DE / DEC L / JP NZ
```

16 bytes copiados a `$0000-$000F`, encima del `jp` de `$0005`. El
siguiente `call 5` encuentra `20 20` (`JR NZ`) y descarrila. En el
depurador se veia un deslizamiento por `00 39 00 39` con `SP=$0402`: la
pila tambien destruida.

### El campo

Offset `$47` del SCB = `scb$pg+0E3h` = **`searcha`**, la direccion del FCB
con el que la BDOS esta haciendo la busqueda de directorio en curso.

`ERASE.COM` hace `F_SFIRST` con su FCB en `$006C` y luego pregunta por
ese campo para saber si la BDOS esta usando ese mismo FCB. El codigo es
defensivo:

```
$0613  CALL $0EAA      ; HL = $006C - (0F3D)
$0616  OR L
$0617  JP Z,$062D      ; si coinciden, no copiar
```

Con `searcha` = `$006C` la comprobacion salta y no se copia nada. Con
`searcha` = 0 la resta da `$006C`, no salta, y copia a la direccion 0.

### Por que estaba a cero

Esto **venia de DRI**, no lo rompimos nosotros. En `CPMBDOS2.ASM:176`:

```
;searcha	equ	scb$pg+0e3h
```

...comentado. Y mas abajo, dentro de un `[if BANKED]`, `searcha` se
declara como variable del **dseg** -- que en un sistema bancado vive en
el banco de sistema. En nuestro mapa acabo en `$B2A0`. Ahi ningun
programa puede leerla, y el campo `+47h` del SCB se queda a cero para
siempre.

El sitio estaba reservado: `dcnt` ocupa `$E0E1-$E0E2` y `searchl` empieza
en `$E0E5`. Esos dos bytes estan libres exactamente para esto.

Arreglo: descomentar el `equ` y quitar el `ds word` del dseg. De los 58
campos del bloque de equates del SCB, era **el unico** comentado; los
otros 57 ya apuntaban a la pagina comun.

**Leccion**: de los campos del SCB que hemos tenido que arreglar --
`?ERJMP`, la direccion del SCB, `conwidth`/`conpage`, `commonbase`,
`rubout$act`, `bdosbase` y ahora `searcha` -- todos menos este eran
trabajo de GENSYS que nos saltamos. Este es distinto: es un campo que
la propia fuente de DRI deja muerto en la configuracion bancada. Merece
la pena repasar el bloque entero buscando mas casos asi, en vez de
seguir esperando a que tropiece la siguiente utilidad.

## Repaso completo del SCB: las dos clases de campo muerto

Tras lo de `searcha` convenia dejar de descubrir campos de uno en uno,
cada vez que tropieza una utilidad nueva. Son dos problemas distintos y
se buscan de forma distinta.

### Pasada 1 -- campos que rellenaria GENSYS

Metodo: para cada campo del bloque de equates, contar referencias en la
BDOS y mirar si alguna ESCRIBE. Los que solo se leen necesitan valor
inicial, y sin GENSYS ese valor no existe.

| Campo | SCB+ | Valor | Por que |
|---|---|---|---|
| `version` | `+05` | `$31` | `func12` hace `lda version`. A cero, la funcion 12 responde "no soy CP/M 3" |
| `multcnt` | `+4A` | `1` | La BDOS lo lee en 3 sitios y solo lo escribe la funcion 44. DRI: *"If mult$cnt ~= 1 then bd$read or bd$write commands"* |
| `outdelim` | `+37` | `'$'` | `print` compara contra su CONTENIDO. A cero, la funcion 9 termina en un byte nulo en vez de en `'$'` |

Ese ultimo es el mas silencioso de los tres: la funcion 9 sigue
imprimiendo, solo que de mas, hasta encontrar un cero.

Revisados los 58 campos. `errormode` (`+4B`), `ctlh$act` (`+2E`),
`page$mode` (`+2C`) y `type$ahead` (`+30`) se quedan a cero **a
proposito**: cero es su valor correcto por defecto. Los que ya
poniamos (`?ERJMP`, `scbadd`, `conwidth`/`conpage`, `commonbase`,
`rubout$act`, `bdosbase`, los cinco vectores de redireccion) siguen
igual.

### Pasada 2 -- campos que la fuente de DRI deja muertos

Metodo distinto: no mirar `?init`, sino buscar **variables declaradas en
el dseg de la BDOS cuyo nombre aparezca tambien como equate comentado
hacia `scb$pg`**. Esas caen en el banco de sistema y el campo del SCB se
queda sin dueno.

Resultado: `searcha` era **el unico**, en `BDOS.ASM` y en el original
`dri_src/CPMBDOS2.ASM`. Los otros 57 equates estan vivos.

Comprobado ademas que el mapa de `$E000-$E0FF` no tiene huecos sin
explicar: cada salto entre campos consecutivos corresponde al tamano
real del campo anterior.

**Leccion**: las dos pasadas encontraron cosas distintas y ninguna
habria encontrado lo de la otra. La primera se contesta mirando quien
ESCRIBE cada campo; la segunda, mirando donde ATERRIZA cada variable. Y
la segunda solo es posible porque tenemos la fuente de DRI al lado para
comparar.

## `DEVICE` sacaba "6$" donde debia poner "CON": `@ctbl`

`DEVICE` borraba la pantalla varias veces, imprimia texto sin sentido, y
aun asi llegaba a su pregunta y salia bien con RETURN. El dato que lo
resolvio estaba en el texto: donde tenia que ir el nombre del
dispositivo salia **`6$`**.

```
CONIN:  = 6$          <- deberia ser "CONIN:  = CON"
! NONE  X    6*D NONE  IS    n2: NONE  IX
```

`@ctbl` estaba en `$835C`, en el banco de sistema. `BIOS DEVTBL`
(entrada 20) devuelve esa direccion al programa, que la lee desde el
banco de **usuario** y encuentra TPA.

Y los borrados de pantalla eran el mismo problema: entre la basura que
imprimia habia bytes `$1A`, que nuestro `?co` interpreta como
*clear screen*. Una sola causa para los dos sintomas.

### El fallo de la auditoria anterior

En el repaso de estructuras que entrega la BDOS o el BIOS, `devtbl`
figuraba como correcto:

| Estructura | Donde vive | Estado |
|---|---|---|
| `devtbl` | `$F606` comun | ~~OK~~ |

Se comprobo **la rutina**, no **la tabla que la rutina devuelve**. La
rutina es `lxi h,@ctbl / ret`: lo que el programa lee no es ella, es
`@ctbl`. Mismo despiste que con el DPB, y en la misma lista.

La version corregida de esa auditoria:

| Entrada | Devuelve | Donde vivia | Estado |
|---|---|---|---|
| BDOS 31 | DPB | sistema | movido a `$F775` |
| BDOS 49 | campos del SCB | comun | OK |
| BDOS 27 | ALV | sistema | **sigue roto** (1 KB, no cabe) |
| BIOS 9 SELDSK | DPH | sistema | movido a `$F618` |
| BIOS 20 DEVTBL | **`@ctbl`** | sistema | movido a `$F797` |
| BIOS 22 DRVTBL | `@dtbl` | sistema | movido a `$F618` |
| BIOS 16 SECTRAN | XLT del DPH | -- | vale 0, sin tabla de skew |

**Leccion**: la pregunta correcta no es "¿esta la rutina en memoria
comun?" sino "¿que direccion acaba en manos del programa, y puede
leerla desde su banco?". Una rutina que devuelve un puntero no protege
nada por estar bien colocada.

## `DEVICE`, segunda parte: la funcion 50 estaba rota a proposito

Mover `@ctbl` a memoria comun no arreglo nada: seguia saliendo `6$`. Y
un breakpoint en `devtbl` (la rutina del BIOS) **no disparaba nunca**, o
sea que `DEVICE` no llegaba a ella por ningun camino.

La razon estaba en `BDOS.ASM`, y escrita a mano por nosotros:

```
; func50 queda roto a proposito -- es una funcion BDOS rara, de muy
; bajo uso (acceso directo al BIOS saltandose la BDOS). Alias solo
; para que compile; NO llamar a funcion 50.
bios	equ	?boot
```

La **funcion 50** (llamada directa al BIOS) calcula la entrada asi:

```
	lxi h,bios
	add l
	mov l,a        ; bios + 3*numero_de_funcion
```

...o sea que da por hecho **zancada de 3 bytes**. Es el mismo supuesto
que rompio a Turbo Pascal, solo que desde dentro de la BDOS en vez de
desde el programa. Con `bios = ?boot` (la tabla real, de zancada
variable), `bios + 3*20` cae a mitad de una entrada.

`DEVICE` pide la tabla de dispositivos con `func50`+`BIOS 20`. De ahi los
nombres tipo `6$` y los borrados de pantalla, que eran bytes `$1A`
sueltos entre la basura.

El arreglo es una linea, porque la tabla de zancada fija ya existe desde
que arreglamos lo de Turbo Pascal:

```
bios	equ	BIOSTBL
```

`bios$tbl` existe identica en los dos bancos, asi que vale para el
programa (via `$0001`) y para la BDOS.

### Y de paso, `badfunc` otra vez

En el mismo bloque:

```
dirbios4	equ	dir$bios2
```

`dir$bios4` **existe**, unas lineas debajo de `dir$bios3`. Pero el salto
de `func50` la escribe `dirbios4`, sin el `$`, y en MAC/RMAC el `$`
dentro de un identificador se ignora -- son el mismo simbolo. zmac los
trata como distintos, y alguien "resolvio" el simbolo indefinido
aliasandolo a `dir$bios2`, **suplantando el manejador real**.

Es el mismo bug que `badfunc`/`bad$func` en `RESBDOS.ASM`, con la misma
forma: no falla, suplanta. `dir$bios4` es el post-proceso de una llamada
directa a SELDSK, que traduce el DPH devuelto.

No se habia notado porque `func50` estaba rota de todas formas.

**Leccion**: "roto a proposito porque casi nadie lo usa" es una apuesta,
y esta se perdio. Cuando la nota que justifica dejar algo roto dice "de
muy bajo uso", conviene anotar que sigue pendiente en vez de darlo por
cerrado -- sobre todo si, como aqui, la pieza que falta acaba
apareciendo por otro motivo un mes despues.

## El reloj: `?time` (rtc.z80)

`?time` era un `ret` desde el principio. Ahora habla con el RTC del MCU.

### El contrato

Entrada 26 del BIOS: `C=0` leer, `C=0FFh` poner. Al leer hay que
actualizar cuatro campos del SCB:

| Campo | SCB+ | Formato |
|---|---|---|
| `@DATE` | `+58` | palabra, dias desde el 1-1-1978 (ese dia es el 1) |
| `@HOUR` | `+5A` | BCD |
| `@MIN` | `+5B` | BCD |
| `@SEC` | `+5C` | BCD |

Y hay un requisito que no esta en la guia sino en un comentario del
llamante (`BDOS.ASM:6582`):

```
	mvi	c,0
	call	timef ; does not modify hl,de
```

**`?time` tiene que preservar HL y DE.** El cuerpo los usa todos, asi
que se salvan en la entrada.

### El protocolo

`cmd_rtc` es el comando **50** del MCU. Para leer: dos envios y
veintitres recepciones, la misma forma que `sd_fread`.

```
Z80 -> 50           comando
MCU <- ToggleClock  (ACK)
Z80 -> 0            param_len = 0 significa "dame la hora"
MCU -> 22 bytes     "yyyy-mm-dd hh:mm:ss.cc"
MCU -> 1 byte       estado
MCU <- ToggleClock  (final)
```

La trampa: el firmware traduce la cadena con `asc_to_asc81` antes de
mandarla, asi que **los digitos no llegan en ASCII sino en codigos
ZX81** (`$1C`-`$25`, GLOBALS.cpp). El valor numerico es `byte - $1C`.
Los separadores se ignoran porque las posiciones son fijas.

Cuesta unos 22 ms por lectura: el firmware hace `delay(1)` por byte. La
aritmetica del lado Z80 es despreciable al lado de eso.

### La conversion de fecha

```
dias = 365*(ano-1978) + (ano-1977)/4 + acumulado[mes] + dia
       + 1 si el ano en curso es bisiesto y ya paso febrero
```

`(ano-1977)/4` cuenta los bisiestos ya pasados: el primero es 1980.
Comprobado 1978->0, 1981->1, 2026->12. La regla simple de "divisible
por 4" vale de 1901 a 2099, que sobra.

Verificado contra las 44.560 fechas entre el 1-1-1978 y el 31-12-2099:
**cero discrepancias**. El maximo, 44560, cabe holgado en la palabra.

### Lo que falta

**Poner la hora (`C=0FFh`) no esta.** Exige la conversion inversa --
dias desde 1978 de vuelta a ano/mes/dia, que es un bucle de restas -- y
formatear los 22 bytes. Mientras tanto `DATE SET` no hace nada, pero
tampoco estropea la hora que ya lleva el MCU.

Y para que `DIR [FULL]` ensene fechas hace falta ademas que el disco
tenga entradas SFCB, que las crea `INITDIR`. Leer la hora es condicion
necesaria, no suficiente.

### Poner la hora

`C=0FFh` ya esta. Es la lectura al reves, y la parte incomoda es
deshacer `@DATE`: sin division, hay que ir restando anos completos (365
o 366) y luego meses. Verificado en Python **ida y vuelta** sobre las
44.560 fechas de 1978 a 2099, sin una discrepancia.

La hora no hace falta convertirla: `@HOUR`/`@MIN`/`@SEC` ya vienen en
BCD, asi que **cada nibble ES el digito** -- `put_bcd` es cuatro
instrucciones. Las centesimas se mandan a `00` porque el SCB no las
tiene.

**Limitacion del firmware**: `cmd_rtc` hace `year %= 100` al guardar y
`rtc_get_time` devuelve `getYear()+2000`, asi que el MCU solo entiende
el siglo XXI. Poner una fecha anterior al 2000 la devolveria con 2000
sumados. El sitio de arreglar eso es el firmware, no el XIOS.

### Y el ano que enseña `DATE`

`DATE` muestra `Mon 09/14/<6`. Dia de la semana, mes, dia y hora
correctos; el ano sale `<6` en vez de `26`.

No es fallo nuestro: `DATE.COM` calcula el ano como *anos desde 1900* --
2026 da **126** -- y lo mete en un campo de dos digitos. `'0'+12` es
`$3C`, que es `<`. En 1983 eso daba `83` y cabia.

**Una maquina CP/M 3 real en 2026 mostraria exactamente lo mismo.** El
formato de fecha de CP/M 3 aguanta hasta 2157 en su palabra de 16 bits;
el limite esta en las utilidades. Los sellos de fichero no se ven
afectados.

Se descarto desfasar el reloj 28 anos (1998 y 2026 tienen calendarios
identicos, comprobado mes a mes) porque eso seria apartarse de lo que
hace una maquina real para que una utilidad de 1983 quede contenta. Si
alguna vez molesta, el sitio de arreglarlo es `DATE.COM`.

## Sellos de fecha: INITDIR, la etiqueta, y los .COM con RSX

Con `?time` funcionando, `DIR [FULL]` seguia sin ensenar fechas. Hacian
falta dos piezas mas, y por el camino aparecio un agujero del cargador.

### Son tres cosas, no una

1. **`?time`** -- leer el reloj. Ya estaba.
2. **`INITDIR`** -- crea las ranuras fisicas: una entrada SFCB (primer
   byte `$21`) por cada tres ficheros. Funciono a la primera: 64 SFCB,
   uno de cada cuatro exactamente.
3. **La etiqueta de disco** -- una entrada `$20` cuyo byte 12 dice si hay
   que rellenar esas ranuras. **Sin ella la BDOS ve las ranuras y no
   escribe nada.**

Los bits del byte de modo, comprobados contra la fuente de la BDOS y no
contra la documentacion:

| Bit | Mascara | Significado | Donde se ve |
|---|---|---|---|
| 0 | `$01` | la etiqueta existe | |
| 4 | `$10` | sello de creacion | `make3a: mvi c,01010000b` |
| 5 | `$20` | sello de modificacion | `update$stamp: mvi c,00100000b` |
| 6 | `$40` | sello de acceso | apertura: `mvi c,01000000b` |
| 7 | `$80` | contrasenas | |

### Por que no servia `SET`

`SET [CREATE=ON,UPDATE=ON]` volvia al prompt sin decir nada y sin
escribir la etiqueta. La traza a nivel de BDOS era: cargar, una llamada
`$31`, una `$62`, cuatro caracteres, y fuera.

Se perdio bastante tiempo analizando ese tramo como si fuera `SET`
cuando era **la CCP reiniciandose**: todas las direcciones estaban entre
`$0100` y `$0AFF`, que es justo donde vive la CCP. Hasta el `$62` encaja
-- es el `reset$alloc` de la CCP (`mvi c,allocf`, con `allocf` = 98).

La causa de verdad estaba en el fichero:

```
$0100: C9 80 22 C9 ...                  C9 = RET
$010F: 01 80 23 1E 04 FF 00 "DIRLBL  "
$0200: 31 A8 21 C3 4D 0A                LD SP,$21A8 / JP $0A4D
```

**`SET.COM` es un `.COM` con prefijo RSX.** Empieza con un `RET` -- para
fallar sin estropicio en un CP/M 2.2 -- declara un modulo residente
llamado `DIRLBL`, y el programa de verdad empieza en `$0200`.

Nuestro `loader.z80` lee el fichero en crudo a `$0100` y salta ahi: se
come el `C9`, hace `RET` y se va al arranque en caliente. De ahi el
silencio absoluto.

Son **cinco** las utilidades afectadas, y fallan todas igual:

| Utilidad | RSX |
|---|---|
| `SET.COM` | `DIRLBL` |
| `GET.COM` | `GET` |
| `PUT.COM` | `PUT` |
| `SAVE.COM` | `SAVE` |
| `SUBMIT.COM` | `SUB` |

Las otras 24 del disco son `.COM` planos y por eso funcionan.

### El atajo: `setlabel.py`

Escribe la entrada `$20` directamente en la imagen desde el anfitrion.
Son 32 bytes y evita las posiciones multiplo de 4 menos 1, reservadas
para los SFCB.

Con eso, `PIP` de un fichero nuevo y `DIR [FULL]` ya ensena las columnas
`Prot`, `Update` y `Create` con la fecha y hora del RTC. **El circuito
queda cerrado de punta a punta**: MCU -> `?time` -> BDOS -> SFCB -> DIR.

El ano sale `<6` por el Y2K de las utilidades, como en `DATE`.

**Leccion**: cuando una direccion que aparece en una traza cae dentro
del rango de la CCP (`$0100-$0AFF`), lo primero es preguntarse si lo que
se esta trazando es el transitorio o la CCP. Un transitorio que falla
nada mas arrancar devuelve el control a la CCP, y a partir de ahi lo que
se ve es codigo de la CCP en las mismas direcciones donde estaba el
programa.

## `SET` pedia INITDIR sobre un disco ya formateado: `@dbnk` en `setdma`

Con las SFCB ya funcionando, `SET C:[create=on,update=on]` contestaba:

```
ERROR: Directory needs to be re-formatted for time/date stamps.
       Please see INITDIR.
```

...sobre un `C.IMG` que, inspeccionado desde el anfitrion, tenia las 64
SFCB en su sitio (una cada cuatro entradas, en 3, 7, 11...), la etiqueta
`$20` en la entrada 40 con modo `$31`, y fechas reales grabadas.

### No era el disco, y no era la BDOS

Un BP en `func100` (`$B0A6`, *Set Directory Label*) **no saltaba nunca**.
La comprobacion no la hace la BDOS: la hace el RSX **`DIRLBL`** que
`SET.COM` lleva dentro, y que intercepta la funcion 100 antes de que
llegue a la BDOS.

Sobre el binario se ve el bucle, en el offset `$90` del modulo:

```
0181: call 02B6        ; trae el registro de directorio
0187: lxi d,0020h      ; 32 = tamano de entrada
018E: dad d            ; bucle: hl += 32
018F: mov a,m
0190: cpi 21h          ; ¿SFCB?
0192: jz  01AB         ;   si -> todo correcto
019E: jnz 018E
01A5: jnz 0222         ; -> el mensaje
```

Y lo importante: **`DIRLBL` lee el directorio por BIOS directo**, con la
tabla de saltos de `$0001`, no por la BDOS. Sus thunks son todos de la
forma `lxi d,<off> / lhld 0001 / dad d / lxi d,0 / pchl`:

| offset | entrada | funcion |
|---|---|---|
| `+$18` | 9 | SELDSK |
| `+$1B` | 10 | SETTRK |
| `+$1E` | 11 | SETSEC |
| `+$21` | 12 | SETDMA |
| `+$24` | 13 | READ |
| `+$27` | 14 | WRITE |

**No hay `+$51` (SETBNK, entrada 28) en ninguna parte del modulo.** O sea
que `DIRLBL` no dice nunca en que banco esta su buffer: da por hecha la
semantica que el propio DRI documenta en `setdma` (BIOSKRNL.ASM):

> *Set Disk Memory Address. Saves DMA address from `<BC>` in `@DMA` and
> **sets `@DBNK` to `@CBNK`** so that further disk operations take place
> in current bank.*

Es la misma regla que DRI aplica a mano en el post-proceso de la funcion
50 (`BDOS.ASM:7541`): si la funcion BIOS pedida es la 12 (SETDMA), apila
`dir$bios3`, que es `mvi a,1 / jmp setbnkf` -- "el DMA esta en el banco
de USUARIO".

### Lo que la rompia

`?stdma` pasa por `biosd`, y `biosd` hace `xor a / call bnksel` para
ponerse en sistema. Pero `bnksel` es `sta @cbnk / jmp ?bank`: **cuando
`setdma` ejecutaba `lda @cbnk`, ya valia 0**.

Resultado: `@dbnk = 0` siempre. Con `@dma = $8245` (el buffer de
`DIRLBL`, en el banco de usuario) y `@dbnk = @cbnk = 0`, `xfer$out` ni
siquiera conmutaba el paginado: copiaba los 128 bytes a `$8245` **del
banco de sistema**, que es codigo del propio XIOS (`sd_read` esta en
`$8047`). `DIRLBL` escaneaba un buffer que nunca se rellenaba.

Con la BDOS no se notaba porque efectivamente llama desde el banco 0, y
ademas corrige con `setbnkf` justo despues de cada `seek` -- el orden es
siempre SETDMA y luego SETBNK, en los cuatro sitios.

El arreglo es una linea: `lda @cbnk` -> `lda BD_BNK`, el banco del
llamante que `biosd` ya guarda en banco 7. Para la BDOS vale 0 igual que
antes; para un programa vale 1, que es lo que quiere DRI.

**Leccion**: `biosd` resuelve el cambio de banco de las entradas de
disco, pero al hacerlo **destruye el contexto que algunas rutinas de
DRI leen como dato**. `@cbnk` dejo de significar "el banco del que
llama" en cuanto metimos un cambio de paginado por delante. Cualquier
rutina del BIOS que consulte `@cbnk` hay que revisarla con esa lente, y
usar `BD_BNK` en su lugar.

**Y una tecnica**: la tabla `bios$tbl` (`$DC80`) es un punto de ruptura
limpio para aislar a los programas que llaman al BIOS por `$0001`. La
BDOS entra por las direcciones reales de las rutinas, asi que un BP en
una entrada de la tabla **solo lo dispara un transitorio**. Aqui,
`$DCA7` (READ) sirvio para pillar a `DIRLBL` sin ruido de fondo.

## Los RSX temporales no se desenganchaban nunca: `rsx$chain`

Al quitar `LOADER3.ASM` de la CCP, `rsx$chain` se dejo como un `ret` con
esta excusa: *"sin loader nunca se carga ningun RSX"*. Dejo de ser cierto
en cuanto el cargador aprendio a cargarlos, y el no-op paso a ser un
fallo: **ningun modulo temporal (REMOV <> 0) se desenganchaba**. `GET`,
`PUT`, `SUB` y `DIRLBL` quedaban residentes para siempre y el TPA no se
recuperaba -- cada `SET` se comia su kilobyte largo y no lo devolvia.

La cadena, tal como la monta `ldr$rsx`:

```
$0006 -> base+06 del primer modulo (el ultimo cargado, y el mas bajo:
         se apilan hacia abajo)
base+06  jmp start
base+09  jmp next    <- el operando (base+0Ah) apunta al base+06 del
                       siguiente eslabon
base+0Eh REMOV
```

El ultimo `next` apunta a `LDR_BASE`, que **no es un modulo** (no tiene
prefijo): es la entrada del cargador, y esa es la marca de fin.

`rsx$chain` recorre desde `$0006`, avanza mientras la cabeza sea temporal
y deja coherentes los tres campos que escribe `ldr$rsx` -- `$0006`,
`@MXTPA` y `bdosbase` -- con los valores de `init.z80` (`LDR_BASE` los
tres) si la cadena queda vacia.

Solo desengancha los temporales **de la cabeza**, y es deliberado: al
apilarse hacia abajo, la cabeza es el modulo mas bajo y quitarla es lo
unico que devuelve TPA. Uno enterrado detras de un permanente se queda --
desenlazarlo dejaria un hueco, y compactar exigiria re-relocalizar sin
tener ya el mapa de bits. DRI tiene la misma limitacion.

### Como se comprueba

`$0006` **es** la medida del TPA. Arranque en frio: `$DA00`. Tras un
`SET`, baja al modulo. Tras el siguiente comando, debe volver a `$DA00`.

### Dos trampas que costaron una vuelta

**El REMOV no siempre significa "quitame".** `GET` usa ese mismo byte
como **contador de anidamiento**: `lxi h,010Eh / dcr m`. Con `GET`
enganchado y a la espera vale 0, o sea "permanente", y `rsx$chain` lo
respeta. Correcto, pero no sirve para validar nada: la prueba limpia es
con `SET`/`DIRLBL`, que si lo usa como bandera.

**`ccp_image.z80` llevaba el tamano a mano** en dos equates
(`ccp$image$len`/`ccp$image$padlen`). Cualquier cambio en la CCP obliga a
rehacerlos, y olvidarse significa copiar de menos -- la CCP se carga
truncada. Ahora lo genera `mkccpimg.py` desde `build_ccp.bat`, que ademas
aborta si la imagen desborda `$C800` (donde empiezan los ALV). Margen
actual: 256 B.

### Lo que queda

Nadie pone `rsx$only$set` (bit 1 de `ccpflag1`) -- lo hacia el
`LOADER3.ASM` eliminado -- asi que `rsx$chain` se ejecuta en todos los
arranques en caliente, incluido el inmediatamente posterior a cargar un
RSX. Para un `.COM` de cuerpo nulo **y** temporal eso lo quitaria antes de
poder usarse. De los cinco casos reales el unico de cuerpo nulo es
`SAVE`, que es permanente, asi que hoy no afecta; si aparece el caso, el
arreglo es que `ldr$rsx` marque ese bit.
