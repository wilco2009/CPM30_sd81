> **Nota de integración** (borrar esta nota al pegar en el manual): este
> capítulo asume que el lector ya conoce el SD81 Booster (hardware,
> instalación, tarjeta SD) por los capítulos anteriores del manual, así
> que no repite esa introducción. Encaja de forma natural como capítulo
> nuevo, después de "11. Gestión de memoria" (comparte el concepto de
> paginación en bloques de 8 KB) o al final, junto a "15. Para
> programadores" (mismo registro técnico). La sección "Escritura (OUT
> 7FEFh)" de ese capítulo 15 ya documenta el registro de color de
> borde citado más abajo en BORDER — puede enlazarse en vez de
> repetirse. Faltaría numerar los encabezados y añadir las entradas al
> índice.

# CP/M — un sistema operativo alternativo

Además del BASIC de serie del ZX81, el SD81 Booster puede arrancar
**CP/M**, el sistema operativo estándar de los microordenadores
profesionales de 8 bits de finales de los 70 y los 80. Existen dos
puertos para este hardware:

- **CP/M 2.2**, la versión clásica, sin bancos de memoria: hasta unos
  41 KB de TPA (área de programa transitorio) en modo MC45.
- **CP/M 3 (CP/M Plus) bancado**, que usa el paginador de memoria del
  SD81 Booster para repartir la RAM en bancos de 8 KB independientes de
  sistema y de usuario. Es el que documenta este capítulo.

CP/M 3 aporta, sobre el 2.2: más TPA (el sistema y el usuario ya no
comparten el mismo banco), un disco RAM, el reloj en tiempo real
integrado en el sellado de fecha de los ficheros, una consola con 256
caracteres y color, y un driver de red para BBS y sistemas de
comunicaciones por WiFi.

El sistema sigue el estándar de Digital Research (DRI) hasta donde el
hardware lo permite: mismo formato de CCP, BDOS y BIOS, mismas
convenciones de programa `.COM`, misma tabla pública de llamadas al
BIOS. Lo específico de este puerto es la capa de paginación de memoria
(el XIOS) y los drivers de dispositivo — disco, teclado, consola,
reloj y red — escritos para el hardware del SD81 Booster.

## CP/M 2.2: los dos modos de compilación

CP/M 2.2 se distribuye en dos variantes, seleccionadas al compilar
(`config.inc`), según se use o no el modo **MC45**:

| Modo | MC45 | TPA | RAM de vídeo | Recomendado para |
|---|---|---|---|---|
| 32 KB | No | ~24 KB | `$8000` | Uso general de CP/M |
| 48 KB | Sí | ~41 KB | `$C000` | Turbo Pascal y programas grandes |

El modo de 32 KB funciona en cualquier SD81 Booster sin nada especial
que activar. El de 48 KB necesita MC45 encendido, y da casi el doble
de TPA — la diferencia entre poder compilar con Turbo Pascal o no.

### Qué es MC45, y por qué hace falta

El ZX81, en su modo de vídeo estándar, genera cada línea horizontal de
la pantalla **ejecutando literalmente el propio buffer de vídeo** como
si fueran instrucciones de máquina: mientras dura esa línea, un
circuito sustituye el contenido del bus de datos por ceros, forzando
`NOP` en cada ciclo, hasta que se llega al final de línea — un `HALT`
de verdad — que libera al generador y deja a la CPU ejecutar ese
`HALT`.

![Circuito generador de NOPs (referencia: esquema del ZX80, funcionalmente equivalente al del ZX81 en este punto)](zx80_nop_generator_ref.png)

El circuito (IC15.2 en el esquema de referencia del ZX80) fuerza el
bus de datos a cero mediante ocho puertas NOT de colector abierto,
activas cuando se cumplen a la vez: `/HALT=0`, `/M1` (ciclo de
búsqueda de instrucción), `A15=1` y `D6=0`. La condición sobre `D6` es
la que distingue los caracteres normales (bit 6 a cero, se convierten
en `NOP`) del propio `HALT` de fin de línea (opcode `$76` = `0111
0110`, con el bit 6 a uno) — así el circuito sabe cuándo parar sin
necesitar nada más.

Ese mismo mecanismo, necesario para el vídeo nativo, es lo que impide
ejecutar código de verdad en los bloques 4 y 5 (direcciones
32768-49151): cualquier byte con `D6=0` que caiga ahí durante un ciclo
de búsqueda de instrucción se convierte en `NOP`, tenga o no relación
alguna con generar vídeo.

**MC45 engaña a ese circuito forzando la señal `/HALT` a cero** de
forma intermitente, durante los ciclos de búsqueda de instrucción en
la zona cubierta. Con `/HALT` ya a cero, la condición nunca se cumple
tal y como la espera el circuito, y el código se ejecuta sin que se le
sustituya nada. Es seguro porque los bloques 4/5 nunca coinciden con
el buffer de vídeo desplazado en uso normal.

> **Aviso.** `/HALT` es, en condiciones normales, una señal que
> controla el propio Z80, no la FPGA: con MC45 activo, la FPGA la
> fuerza externamente y de forma intermitente durante los ciclos de
> búsqueda de instrucción en la zona cubierta. Esto no tiene por qué
> suponer ningún problema, y las pruebas hechas hasta ahora — extensas
> — no han mostrado ninguno. Pero no hay garantía absoluta de que
> forzar esa señal, sostenido en el tiempo, no acabe teniendo algún
> efecto de desgaste sobre ella o sobre la patilla de la FPGA que la
> controla. El uso de MC45 se hace bajo la responsabilidad del
> usuario.

### La extensión a los bloques 6 y 7

CP/M 3 necesita **toda** la memoria por encima de los 32 KB para su
paginación en bancos, no solo los bloques 4 y 5 — de ahí que use una
extensión de MC45 que cubre también los bloques 6 y 7 (49152-65535),
activada escribiendo `170` en el registro de control correspondiente
(`POKE 2062,170` desde BASIC; el propio arranque de CP/M 3 lo hace por
su cuenta, sin que el usuario tenga que hacer nada).

Esta extensión solo es segura cuando nada en el sistema va a ejecutar
el buffer de vídeo desplazado mientras está activa, y CP/M 3 lo
garantiza por construcción: no genera vídeo nativo de esa forma en
ningún momento, así que los bloques 6/7 quedan libres para ejecutar
código real sin ningún riesgo adicional sobre el que ya supone MC45 en
sí mismo.

## Instalación y arranque

El sistema se distribuye como un único fichero, `SYSTEM.BIN`, que
contiene el BIOS, la BDOS y el CCP ya enlazados. Se carga desde BASIC
igual que cualquier bloque de código máquina y se arranca con `USR`:

```
LOAD FAST "SYSTEM.BIN" CODE 24576
RAND USR 24576
```

Además de `SYSTEM.BIN`, la tarjeta necesita las imágenes de disco:
`A.IMG` a `D.IMG` (256 KB de directorio, 2 MB de datos cada una) en la
raíz de la SD. Las imágenes de CP/M 3 tienen un formato propio y **no**
son compatibles con las de CP/M 2.2 ni con las de BASIC — no se pueden
mezclar. Una quinta unidad, `E:`, es un disco RAM que no necesita
imagen: se crea vacío en cada arranque y su contenido se pierde al
apagar o resetear.

## Particularidades de este CP/M

### Memoria bancada

El SD81 Booster pagina la memoria en 8 bloques de 8 KB. CP/M 3 usa esa
capacidad para mantener **dos contextos** completos: uno de sistema
(donde vive el BIOS y la BDOS) y uno de usuario (la TPA, donde corren
los programas). El bloque más alto (`$E000`-`$FFFF`) es común a los
dos contextos — ahí vive todo lo que necesita ser alcanzable sin
importar cuál esté activo, incluida la tabla pública de llamadas al
BIOS (ver más abajo).

Esto solo es posible por encima de los 32 KB gracias a la extensión de
MC45 a los bloques 6 y 7 — ver "CP/M 2.2: los dos modos de
compilación" más arriba para el mecanismo completo. CP/M 3 la activa
solo al arrancar, sin intervención del usuario.

Un programa de usuario no necesita saber nada de esto: el cambio de
contexto lo gestiona el propio sistema en cada llamada a la BDOS o al
BIOS. Solo importa si se escribe código que accede a memoria fuera de
la TPA, o que necesita ir más rápido que una llamada normal a la BDOS
(ver "Llamar al BIOS directamente").

### Discos: `A:`-`D:` (tarjeta SD) y `E:` (RAM)

`A:` a `D:` son las cuatro unidades respaldadas por la tarjeta SD, con
formato CP/M 3 estándar (2 KB por bloque de asignación, 256 entradas
de directorio). `E:` es un disco RAM de unos 390 KB, rápido pero
volátil — útil para compilaciones, ficheros temporales o cualquier
cosa que no necesite sobrevivir a un reset.

`MOUNT3.COM` permite cambiar en caliente la imagen montada en una
unidad sin reiniciar el sistema — necesario para intercambiar
disquetes virtuales durante una sesión larga.

### Teclado

El ZX81 no tiene teclado ASCII completo: le faltan símbolos, y solo
tiene una tecla de flecha por combinación con `SHIFT`. La tabla
siguiente resume cómo se llega a cada carácter. Ver el apéndice
"Tabla de teclado" para el listado completo.

- **Directa** y **`SHIFT`+tecla**: letras, dígitos y las flechas
  (estilo WordStar: `SHIFT`+5/6/7/8 = izquierda/abajo/arriba/derecha).
- **`ENTER`+tecla**: los símbolos que el ZX81 no tiene serigrafiados
  directamente — incluidos los que hacen falta para programar en C o
  usar una BBS (`@ \ | ~ \` _ # % & !`, entre otros).
- **`SHIFT`+`ENTER`, y luego una tecla**: modo control. Da `^A`-`^Z`
  con las letras, y `NUL` con la barra espaciadora.
- **`SHIFT`+9** y **`SHIFT`+0**: retroceso (`BS`, `$08`) y borrado
  (`DEL`, `$7F`) — las dos, porque distinto software remoto espera un
  byte distinto para la misma función.
- **`SHIFT`+`.`**: tabulador (`TAB`, `$09`).

### Reloj en tiempo real

CP/M 3 sella la fecha y hora de creación/modificación de cada fichero
usando el RTC de la placa. La hora se ajusta con el propio RTC del
SD81 Booster (por ejemplo desde BASIC, o sincronizándolo por NTP si
hay módulo WiFi) — CP/M solo lee lo que el RTC ya tiene.

### Consola: terminal con 256 caracteres y color

La consola local entiende un subconjunto de secuencias ANSI/VT100,
suficiente para BBS, editores de pantalla completa y cualquier
programa que pinte con color:

- Movimiento de cursor: `ESC[fila;colH` (o `f`), `ESC[nA/B/C/D`
  (arriba/abajo/derecha/izquierda), `ESC[s`/`ESC[u` (guardar/restaurar
  posición).
- Borrado: `ESC[2J` (pantalla), `ESC[K` (fin de línea).
- Color: `ESC[...m` (SGR) — ver la utilidad `SGR` más abajo para la
  lista de códigos soportados.
- `ESC[6n` (petición de posición del cursor): se contesta de verdad,
  con `ESC[fila;colR` — necesario porque algunos programas (BBS
  incluidas) miden el tamaño del terminal así antes de arrancar.
- 256 caracteres (juego CP437 completo, no solo el ASCII imprimible).

### Llamar al BIOS directamente

Todas las funciones del BIOS son alcanzables desde un programa de
usuario sin pasar por la BDOS, a través de una tabla pública de saltos
de 3 bytes cada uno, empezando en la dirección `$FF00`:

| Función | Índice | Dirección |
|---|---|---|
| CONST | 2 | `$FF06` |
| CONIN | 3 | `$FF09` |
| CONOUT | 4 | `$FF0C` |
| AUXOUT | 6 | `$FF12` |
| AUXIN | 7 | `$FF15` |
| AUXIST | 18 | `$FF36` |
| AUXOST | 19 | `$FF39` |

(dirección = `$FF00 + índice × 3`; la lista completa de 33 entradas
sigue el orden estándar de CP/M 3).

Es la misma técnica que usan WordStar y Turbo Pascal para no pagar el
coste de la BDOS en operaciones de consola frecuentes, y está pensada
para programas que necesiten el máximo rendimiento posible — por
ejemplo, un terminal de comunicaciones. El programa `TERM` incluido
con el sistema (ver más abajo) es un ejemplo real: llama a `CONOUT`
así, y eso multiplica por varias veces la velocidad de la consola
frente a pasar por la BDOS.

## Comunicaciones

El sistema incluye un driver de red (`NET`) que expone al Z80 un flujo
de bytes crudo, como si tuviera un módem conectado — el propio
software decide qué hacer con ese flujo (por ejemplo, mandar comandos
`AT` para marcar una conexión). El puente WiFi real lo gestiona el
módulo ESP32 de la placa; el Z80 no sabe nada de sockets ni de
direcciones.

### `TERM` — terminal de comunicaciones

`TERM.COM` es el terminal incluido para usar `NET`. A diferencia de un
programa CP/M típico, **no** pasa por el dispositivo lógico `AUX:` ni
por la BDOS: habla con el hardware de red directamente, con el mismo
truco de llamada directa al BIOS descrito arriba para la salida por
pantalla. La razón es de rendimiento — un terminal genérico que
respetara `DEVICE AUX:` sería varias veces más lento — y significa que
`TERM` está pensado específicamente para `NET`, no como sustituto de
un terminal de comunicaciones de propósito general.

Teclas de `TERM` (todas con `ENTER`+tecla):

| Tecla | Función |
|---|---|
| `ENTER`+`0` | Salir |
| `ENTER`+`9` | Conmutar el eco local (verlo escrito mientras se teclea) |
| `ENTER`+`8` | Conmutar el volcado a fichero (con `TERM fichero.BIN`) |

## Utilidades incluidas

| Programa | Función |
|---|---|
| `MOUNT3.COM` | Cambia en caliente la imagen montada en una unidad |
| `TERM.COM` | Terminal de comunicaciones (ver arriba) |
| `CLS.COM` | Borra la pantalla y sitúa el cursor en el origen |
| `SGR.COM` | Cambia el color de tinta/papel de la consola |
| `BORDER.COM` | Cambia el color del borde |

### `CLS`

Sin argumentos. Borra la pantalla.

### `SGR`

```
SGR parámetros
```

Manda la secuencia ANSI `ESC[parámetros m` a la consola. Los
parámetros van separados por `;`, igual que en cualquier terminal
ANSI:

| Código | Efecto |
|---|---|
| `0` | Restaurar los colores por defecto |
| `1` | Tinta brillante |
| `30`-`37` | Color de tinta: negro, rojo, verde, amarillo, azul, magenta, cian, blanco |
| `40`-`47` | Color de papel, misma tabla de colores |

Ejemplos:

```
SGR 0            reset
SGR 33           tinta amarilla
SGR 1;33;44      tinta amarilla brillante, papel azul
```

### `BORDER`

```
BORDER n
```

`n` de 0 a 7 para un color normal, o de 8 a 15 para el mismo color en
versión brillante (mismos números que en `SGR`, sumando 8 para el
brillo). El borde es un registro de la FPGA aparte de la consola: ver
"Escritura (OUT 7FEFh)" en el capítulo de programadores para el
formato completo del puerto.

```
BORDER 4     borde azul
BORDER 12    borde azul brillante
```

## Apéndice A: tabla de teclado

![Teclado del ZX81 con las combinaciones de CP/M](keyboardSD81_CPM.png)

Las teclas `ENTER`+`8` y `ENTER`+`9` se rotulan por su función (`LOG`,
`ECO`) en vez de por el código de control que mandan (`$1E`, `$1C`):
son las que usa `TERM` para su propio menú, y nadie necesita recordar
el nombre ASCII de esos códigos, solo para qué sirven aquí.

| Tecla | Directa | `SHIFT` | `ENTER` |
|---|---|---|---|
| 1 | `1` | `ESC` | `!` |
| 2 | `2` | — | `@` |
| 3 | `3` | — | `#` |
| 4 | `4` | — | `\|` |
| 5 | `5` | ← | `%` |
| 6 | `6` | ↓ | `&` |
| 7 | `7` | ↑ | — |
| 8 | `8` | → | — |
| 9 | `9` | `BS` | `^\` |
| 0 | `0` | `DEL` | `^]` |
| Q | q | Q | `'` |
| W | w | W | `{` |
| E | e | E | `}` |
| R | r | R | `[` |
| T | t | T | `_` |
| Y | y | Y | `]` |
| U | u | U | `$` |
| I | i | I | `(` |
| O | o | O | `)` |
| P | p | P | `"` |
| A | a | A | — |
| S | s | S | `\` |
| D | d | D | — |
| F | f | F | `~` |
| G | g | G | `` ` `` |
| H | h | H | `^` |
| J | j | J | `-` |
| K | k | K | `+` |
| L | l | L | `=` |
| Z | z | Z | `:` |
| X | x | X | `;` |
| C | c | C | `?` |
| V | v | V | `/` |
| B | b | B | `*` |
| N | n | N | `<` |
| M | m | M | `>` |
| `.` | `.` | `TAB` | `,` |
| ESPACIO | espacio | espacio | espacio |
| ENTER | `CR` | `CR` | `CR` |

Además, `SHIFT`+`ENTER` y luego una letra da `^A`-`^Z` (letra `AND
$1F`), y `SHIFT`+`ENTER`+espacio da `NUL`. `ENTER`+`0`/`9`/`8` (`^]`,
`^\`, `^^`) están reservados para `TERM` — ver más arriba.

## Apéndice B: mapa de memoria (resumen)

| Rango | Contenido |
|---|---|
| `$0000`-`$DFFF` | Bancado: TPA (contexto de usuario) o BIOS/BDOS/CCP (contexto de sistema), según cuál esté activo |
| `$E000`-`$FFFF` | Común a los dos contextos: el SCB (`$FE00`), la tabla pública de llamadas al BIOS (`$FF00`), y el resto del estado que tiene que verse igual desde ambos lados |

El tamaño exacto de la TPA depende de la configuración final del
sistema; se puede consultar arrancando y mirando el mensaje inicial de
CP/M 3 (`Banked memory, NN.NK TPA`).
