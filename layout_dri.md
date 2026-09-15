# Auditoria: el layout de memoria de DRI frente al nuestro

Motivo: en las ultimas sesiones, casi todos los fallos dificiles no han
salido del hardware del ZX81 ni del paginado, sino de que **nuestro
layout de memoria comun no es el de DRI**. El software de CP/M 3 da por
hecho ese layout en sitios que no estan documentados en ningun manual y
que solo aparecen cuando una utilidad falla de forma rara. Esta auditoria
pone encima de la mesa que exige DRI, que tenemos, y que costaria
volver al estandar.

Una aclaracion previa que enmarca todo: en 1982 el implementador escribia
**solo el XIOS** y ejecutaba **GENCPM**, que colocaba `BDOS.SPR` y
`RESBDOS.SPR` (binarios reubicables) con el layout garantizado y rellenaba
el SCB. Nosotros reensamblamos desde fuente y colocamos a mano, asi que
hemos heredado un contrato que alli era automatico, sin tener la lista de
lo que ese contrato exige. Esta auditoria es esa lista.


## 1. Lo que fija DRI

`dri_src/RESBDOS.ASM:31-40` es la unica declaracion explicita del layout
que existe en todo el fuente:

```
        org     0000h
base            equ     $
bnkbdos$pg      equ     base+0fc00h
resbdos$pg      equ     base+0fd00h
scb$pg          equ     base+0fe00h
bios$pg         equ     base+0ff00h
```

Cuatro paginas **consecutivas**, y `bios$pg` la ultima. Lo que va en
cada una:

| pagina | contenido | evidencia |
|---|---|---|
| `bnkbdos$pg` | entrada del BDOS bancado en `+06`, `error$jmp` en `+7Ch` | `RESBDOS.ASM:42-43` |
| `resbdos$pg` | pagina base del BDOS residente | solo declarada; 1 uso |
| `scb$pg` | SCB: privados del BDOS por debajo de `+90h`, **publico en `+9Ch`** | `BDOS.ASM:119-209` |
| `bios$pg` | **tabla de saltos del BIOS, 3 bytes por entrada**, 33 entradas | `RESBDOS.ASM:45-75`, 32 usos |

La tabla del BIOS no es un detalle interno: el RESBDOS llama al BIOS
**por ella** (`conoutf equ bios$pg+12`, `setdmaf equ bios$pg+36`...), y
`$0001` apunta a `bios$pg+3`. La zancada fija de 3 bytes es parte del
contrato publico -- la funcion 50 del BDOS calcula `bios + 3*n`.

El mapa del SCB (`BDOS.ASM:119-209`) va de `scb$pg+90h` (`olog`) a
`scb$pg+0FEh` (`bdosadd`). **Por debajo de `+90h` no hay nada definido en
ningun fuente que tengamos.**


## 2. Lo que tenemos

| | DRI | nosotros |
|---|---|---|
| memoria comun | 4 paginas al final de los 64 K | banco 7, `$E000-$FFFF` |
| tabla del BIOS | `bios$pg`, ultima pagina de la comun | `BIOSTBL = $DC80`, **en el banco de usuario**, zona duplicada |
| SCB | `scb$pg`, penultima pagina | `scb$pg = $E000`, **primera** pagina de la comun |
| BDOS residente | `resbdos$pg`, contiguo al SCB | `rb$serial = $F032`, sin relacion fija con `scb$pg` |
| relacion entre paginas | consecutivas y fijas | ninguna |
| relleno del SCB | GENCPM | a mano en `init.z80` |

Los equates de pagina relativa se eliminaron: `BDOS.ASM:72` dice
*"bnkbdos$pg/resbdos$pg/bios$pg (offsets relativos a base)"* sustituidos
por simbolos directos, y `scb$pg equ 0E000h` (`BDOS.ASM:78`) es el unico
que sobrevive.


## 3. Quien depende de cada cosa (evidencia empirica, no teoria)

| software | de que depende | estado |
|---|---|---|
| `DEVICE` | funcion 50 -> `bios + 3*n`, zancada fija | **arreglado** (`bios equ BIOSTBL`) |
| Turbo Pascal | `$0001` -> tabla de zancada fija | **arreglado** (`bios$tbl`) |
| `SET`/`DIRLBL` | BIOS directo por `$0001` + semantica de `@dbnk` en SETDMA | **arreglado** (`lda BD_BNK`) |
| `SAVE` | parchear un `$C3` en **`scb$pg+68h`** | **roto** |
| `GET` | intercepta consola; muy probablemente el mismo parche | **roto** |
| cualquier RSX | cadena en `$0006`, `@MXTPA`, `bdosbase` | **arreglado** (`rsx$chain`) |

Los tres primeros ya nos costaron una sesion cada uno. Los dos que
quedan son la misma clase de problema.


## 4. El caso concreto de SAVE

`SAVE.COM` obtiene `scbadd` (funcion 49, offset `$3A`), se queda con la
pagina, y hace:

```
mvi l,68h / mov a,m / cpi 0C3h    ; espera un JMP en scb$pg+68h
jnz <no hacer nada>
mvi m,21h                          ; lo convierte en LXI H
...
mvi m,0C3h                         ; y lo restaura al despedirse
```

Convertir un `C3` en `21` hace que el salto **no se ejecute** y el flujo
caiga en la instruccion siguiente. En nuestro binario existe exactamente
ese patron, en `$F199`:

```
F185 blk$out0:  lda conmode
F194            ani 10h / jnz sconoutf
F199            jmp conoutf        <- el candidato
F19C            mov e,c / mvi c,conoutfxx / jmp bank$bdos
```

Neutralizarlo desvia la E/S de consola de **ir directa al BIOS** a
**pasar por el BDOS bancado**, que es donde un RSX puede interceptarla.
Ese es el mecanismo entero de GET/PUT/SAVE.

`$F199` es `rb$serial+167h`. Si `rb$serial` estuviera donde DRI lo pone,
ese byte caeria en `scb$pg+68h` y SAVE lo encontraria.


## 5. Lo que NO he podido determinar

**Que pone DRI exactamente en `scb$pg+68h`.** Ni `RESBDOS.ASM` ni
`BDOS.ASM` ensamblan nada por debajo de `scb$pg+90h`; lo colocaria
GENCPM al fundir los modulos. La correspondencia con el `jmp conoutf` de
`blk$out0` es una **inferencia** (encaja el `C3`, encaja el proposito,
encaja el offset con un byte de desfase atribuible a nuestras
modificaciones del RESBDOS), no una certeza.

Consecuencia practica: **el realineado no garantiza que SAVE funcione.**
Para tener certeza haria falta un `CPM3.SYS` estandar de referencia y
mirar que hay en esa direccion.


## 6. Coste del realineado

**CORRECCION IMPORTANTE.** La primera version de esta auditoria decia
que habia "4045 bytes libres y contiguos en `$E100-$F031`". **Es falso.**
Esa cifra salio de medir la ocupacion sobre `system.lst`, y el `.lst`
solo muestra lo que se EMITE en el binario: los buffers de runtime -- que
no se ensamblan, solo se declaran con un `equ` -- no aparecen. En ese
"hueco" viven ATTR y el DFILE.

El mapa real del banco 7 es este:

| rango | uso | bytes |
|---|---|---|
| `$E000-$E0FF` | SCB | 256 |
| `$E100-$E87F` | **ATTR** (`init.z80:41`) | 1920 |
| `$E880-$E898` | libre | 25 |
| `$E899-$F018` | **DFILE** (`chario.z80:24`) | 1920 |
| `$F019-$F031` | libre | 25 |
| `$F032-$F591` | RESBDOS | 1376 |
| `$F592-$F597` | relleno | 6 |
| `$F598-$F7ED` | BIOS | 598 |
| `$F7EE-$F7FF` | libre | 18 |
| `$F800-$FFFF` | tabla de fuentes (con `@BNKBF` y `DISKHANDLE` superpuestos en los glifos no imprimibles) | 2048 |

**El mayor hueco contiguo son 25 bytes.** El banco 7 esta practicamente
lleno, y no cabe ahi nada de tamano apreciable sin mover antes ATTR o el
DFILE.

Comprobado en hardware: con `BIOSTBL` en `$EF00` el sistema arranca pero
se cuelga en cuanto un programa usa la tabla, porque cada escritura en
pantalla la machaca. Turbo Pascal sacaba un "6" en la parte de abajo --
bytes de la tabla interpretados como caracteres.

**Leccion de metodo**: medir el espacio libre del mapa de memoria sobre
el `.lst` NO vale. Solo ve lo ensamblado. Hay que cruzarlo siempre con
los `equ` de buffers (DFILE, ATTR, `@BNKBF`, ALV, los `ds` de la BDOS) y
con `memory_map.md`.

Por orden de coste creciente:

**(a) Mover `BIOSTBL` al banco 7.** Hoy vive en `$DC80`, en el banco de
usuario, y existe por duplicado. En la comun existiria una sola vez y
seria visible desde los dos bancos por construccion -- que es
precisamente lo que la zona duplicada simula. Alinea ademas `bios$pg`
con DRI.

**INTENTADO Y REVERTIDO**: no cabe. Son 100 bytes (33*3+1) y el mayor
hueco contiguo del banco 7 son 25. Para que quepa hay que liberar sitio
antes, y las unicas vias son mover ATTR/DFILE fuera del banco 7, o
compactar la zona de glifos no imprimibles `$F800-$F8FF`, donde hay 112
bytes libres pero en dos trozos (`$F880-$F8A5` = 38 y `$F8B2-$F8FB` =
74) separados por 12 bytes ocupados. Si esos 12 se reubicasen quedarian
124 contiguos y la tabla cabria.

**(b) Recolocar `scb$pg` y el RESBDOS** para que `resbdos$pg`, `scb$pg` y
`bios$pg` queden consecutivas como DRI. Es lo que podria arreglar
SAVE/GET. Toca todos los equates que hoy dependen de `scb$base = $E09C`
y obliga a reverificar el arranque entero.

**(c) Restaurar el orden interno del RESBDOS** byte a byte respecto a
DRI. Solo haria falta si (b) no basta.


## 7. Recomendacion

Hacer **(a)** ya: es barato, no depende de ninguna inferencia, reduce
duplicacion y devuelve TPA.

Antes de **(b)**, conseguir un `CPM3.SYS` estandar y comprobar que hay
en `scb$pg+68h`. Si confirma la inferencia de la seccion 4, (b) esta
justificado y arregla SAVE, GET y PUT de una vez. Si no la confirma,
(b) sigue teniendo valor preventivo pero ya no urgente, y lo razonable
es documentar esas tres utilidades como no soportadas.

Y una regla de metodo para lo que venga: **desviarse del layout de DRI
sale mas caro que el espacio que ahorra.** Cada "simplificacion" de este
proyecto estaba bien razonada en su momento y ahorraba algo real; todas,
sin excepcion, se han cobrado despues una sesion de trazas. Cuando haya
que elegir entre empaquetar y respetar el estandar, respetar el estandar.
