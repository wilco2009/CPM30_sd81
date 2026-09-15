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


---

# Resultado: fases 1 y 2 hechas

## Lo que se hizo

**Fase 1** -- la tabla de fuentes (2 KB) baja del banco 7 al banco de
usuario, en `$D800`. No cabe en cualquier sitio: el modo de 256
caracteres exige alineacion a 2 KB, porque `SD81.v:1089` forma la
direccion como `{ROMTABLE[15:11], caracter, linea}` -- solo los 5 bits
altos del registro I. La zona duplicada baja a `$D500` y el cargador a
`$D200` para que todo quede contiguo.

**Fase 2** -- con el banco 7 liberado:

```
scb$pg    = $FE00     (RESBDOS.ASM:37, literal de DRI)
bios$pg   = $FF00     (RESBDOS.ASM:38, literal de DRI) = BIOSTBL
rb$serial = $F931     para que wbootfx caiga en scb$pg+68h
                      y el modulo termine en scb$pg+90h
```

El cargador sube a `$D300` y baja a 512 B al irse `bios$tbl`. TPA final:
52.5K (era 54.25K). Coste real del realineado: **1.75 K de TPA**.

## El contrato de DRI, ya con nombres

`resbdos$pg` resulto ser **decorativo**: una sola ocurrencia en todo el
fuente, su propia definicion. Lo que de verdad ata son los offsets:

| | |
|---|---|
| `scb$pg+68h` | los thunks parcheables (`wbootfx`, `constfx`...) |
| `scb$pg+90h` | `olog`: aqui empieza el SCB, y aqui debe TERMINAR el BDOS residente |
| `scb$pg+9Ch` | SCB publico (`scb$base`) |
| `scb$pg+100h` | `bios$pg`, la tabla de saltos del BIOS |
| `scb$pg` alineado a pagina | SAVE calcula el thunk como `(scbadd & $FF00) + 68h` |

El codigo del BDOS residente mide lo que quiera: **crece hacia atras**
desde `scb$pg+90h`. Esa es la clave que faltaba, y la que hacia parecer
imposible meter 1376 bytes "en una pagina de 256".

La guarda del final de `RESBDOS.ASM` (`ds SCB_PAGE+90h-$`) verifica el
contrato en cada ensamblado: si el modulo crece o encoge, zmac falla ahi
en vez de dejarlo pasar en silencio.

## Correccion importante: SAVE no estaba roto

Todo el hilo del parche en `scb$pg+68h` nacio de dar por roto a `SAVE`.
**No lo estaba.** La secuencia correcta es:

```
A>save        carga el RSX, no dice nada -- esto es lo normal
A>date        corre el programa que sea
A>save        AHORA aparece el dialogo y guarda
```

En su dia se probo `save` + `date`, no aparecio el cartel, y se dio por
roto. Faltaba el segundo `save`. Confirmado: funciona **con el sistema
de la fase 1**, o sea sin realineado ninguno, y escribe el fichero
correctamente (`TEST.SAV`, `rc=10` = 1280 B = `$6500-$6000` exacto).

El parche del `$C3` es real y forma parte del diseno de SAVE -- desvia
la E/S de consola del BIOS directo al camino bancado, donde los RSX
pueden interceptar -- pero **no hace falta para el flujo normal**.

Asi que la justificacion honesta del realineado no es "arregla SAVE",
sino: alinea el sistema con el estandar y cierra por diseno una clase de
dependencias de layout que ya habia costado cuatro sesiones (`DEVICE`
por la funcion 50, Turbo Pascal por `$0001`, `DIRLBL` por `@dbnk`, y la
propia caceria de SAVE). `GET` sigue pendiente.

**Leccion**: antes de dar por roto el software de DRI, comprobar como se
usa de verdad. Dos de los cuatro "fallos" de SAVE y GET eran expectativas
mias equivocadas, no defectos del puerto.


---

# Estado de los cinco .COM con RSX (2026-09-15)

| utilidad | RSX | estado |
|---|---|---|
| `SET` | `DIRLBL` | **funciona** (arreglado: `@dbnk` en `setdma`) |
| `SAVE` | `SAVE` | **funciona**. Nunca estuvo roto: `save` / programa / `save` |
| `GET` | `GET` | **funciona en modo PROGRAM** (el por defecto). `[SYSTEM]` no |
| `PUT` | `PUT` | **funciona en modo PROGRAM**. `[SYSTEM]` **corrompe memoria** |
| `SUBMIT` | `SUB` | **parcial**: ejecuta el primer comando del `.SUB` y se cuelga en el segundo |

## El patron

Todo lo que redirige **al programa siguiente** funciona. Todo lo que
redirige **al propio CCP** falla:

```
GET [SYSTEM]   entrada de consola del CCP    -> no redirige, silencioso
PUT [SYSTEM]   salida de consola del CCP     -> corrompe memoria
SUBMIT         alimenta comandos al CCP      -> primer comando si, segundo no
```

Tres utilidades distintas y tres mecanismos distintos, con un solo
denominador comun: **el RSX tiene que sobrevivir al arranque en caliente
e interceptar al CCP**. Que SUBMIT ejecute el primer comando y muera en
el segundo encaja exactamente -- entre uno y otro hay un warm boot.

## Sospechosos, por orden de facilidad de descarte

**1. `rsx$chain`.** Es de esta misma manana y desengancha modulos en cada
warm boot. Si desengancha uno que seguia activo, el sintoma seria
justo este. Se descarta en una compilacion: dejarlo como `ret` y repetir
el SUBMIT.

**2. La pila del CCP.** `bdosbase` (`scb$base-4`) marca donde el CCP pone
su pila y el FCB del transitorio, y los modulos RSX se apilan justo
debajo. Si la pila crece mas de lo previsto con un RSX activo, se come
el modulo -- y "corrompe memoria" es literalmente el sintoma de PUT.

**3. El byte alto de `conmode`** (`scb$pg+0D0h`). Es el selector de modo
que lee el RSX de GET (`(conmode_hi & 3) - 1`), y el CCP lo pone a cero
en cada entrada (`scbinit`). Encaja con que SYSTEM no sobreviva... pero
el CCP de DRI hace exactamente lo mismo, asi que falta una pieza.

## Otro detalle sin explicar

El fichero temporal de GET sale en el directorio como `SYSIN51.$$$`. La
cadena del binario es `SYSIN   $$$` (5 letras y 3 espacios), asi que los
caracteres 6 y 7 del nombre llevan basura. No parece critico, pero es un
FCB mal construido y conviene no perderlo de vista.

## Limitacion del emulador a tener en cuenta

Un breakpoint de EJECUCION en `$D300` (`ldr$entry`) no salta nunca,
aunque el cargador se ejecute; uno de ESCRITURA en la misma direccion si.
La hipotesis es que EightyOne ata los breakpoints de ejecucion a la
pagina FISICA mapeada cuando se definen, y el cargador corre en la de
usuario. Antes de concluir nada de un BP que no salta, comprobarlo.


---

# Cierre: los cinco RSX funcionan

| utilidad | RSX | estado |
|---|---|---|
| `SET` | `DIRLBL` | funciona |
| `SAVE` | `SAVE` | funciona (`save` / programa / `save`) |
| `GET` | `GET` | funciona, en `PROGRAM` y en `SYSTEM` |
| `PUT` | `PUT` | funciona, en `PROGRAM` y en `SYSTEM` |
| `SUBMIT` | `SUB` | funciona |

Los tres fallos que quedaban resultaron ser **tres bugs nuestros
distintos**, ninguno relacionado con el layout de DRI:

**1. `rsx$chain` escribia siempre.** Reescribia `$0006`/`@MXTPA`/
`bdosbase` aunque no hubiera desenganchado nada. PUT baja el techo de la
TPA para su buffer de salida, y se lo machacabamos. Arreglo: salir sin
tocar nada si la cabeza de la cadena no ha cambiado.

**2. `ldr$err` tenia un `pop hl` de mas.** A `ldr$entry` se llega por un
SALTO desde `$0006`, asi que la cima de la pila es la direccion de
retorno del que hizo `call 5`; el `pop` se la comia y el `ret` sacaba una
palabra ajena. Solo se llega a esa rama cuando falla el `F_OPEN`, que
tecleando comandos a mano no pasa nunca -- por eso estuvo latente desde
el primer dia.

El sintoma no se parecia en nada a la causa: el `ret` saltaba a `$FF80`
(basura `$FF`, mas alla del final del binario), o sea `RST 38`, que cae
en la pagina cero -- tambien `$FF` -- y se autoalimenta; la pila se
desbordaba 2 KB y el PC acababa deslizandose por el TPA. Con los
registros del cuelgue no habia forma de llegar a la causa. **Lo unico
que sirvio fue la traza de ejecucion hasta el primer `RST 38`.**

**3. `ldr$rsx` reutilizaba modulos muertos.** Buscaba el modulo por
nombre y, si lo encontraba, no lo recargaba. Pero un modulo que ya
termino se marca con `REMOV<>0` y puede seguir enganchado un buen rato.
Arreglo: un modulo marcado para morir cuenta como "no esta".

## La leccion que vale para todo lo que recorra la cadena

**`rsx$chain` solo se ejecuta cuando TERMINA UN TRANSITORIO.** Vive en
`start:` del CCP, y `start:` solo corre tras un arranque en caliente. Los
comandos INTERNOS de la CCP (`DIR`, `TYPE`...) no lo provocan.

Consecuencia: la cadena puede acumular modulos muertos durante un tiempo
indefinido, y cualquier codigo que la recorra tiene que contar con ello.
Fue justo lo que hacia fallar a dos `submit` seguidos con un `.SUB` de
puros comandos internos -- y lo que explicaba que meter un `date` en
medio lo "arreglara", mientras que un `dir` no.
