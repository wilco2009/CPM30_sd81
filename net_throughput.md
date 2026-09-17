# Rendimiento del puente de red — qué mirar en el emulador

Resumen para la sesión del emulador (EightyOne / SD81). Aquí no hace falta
saber nada del puerto de CP/M 3: lo que sigue es autocontenido.

## El síntoma

Un terminal de CP/M 3 sobre el ZX81 (`TERM.COM`) conectado a una BBS real
(Mystic) a través de los comandos MCU 66/67 va **unas 40 veces más lento de
lo que debería**. La sesión funciona —color, ANSI, teclado, todo correcto—
pero el flujo de datos va a paso de tortuga.

## La medida

La propia BBS trae un reloj metido en los datos: durante una cuenta atrás
redibuja el contador **una vez por segundo**, y cada redibujado son **76
bytes** (65 caracteres imprimibles y 10 secuencias de escape; medido sobre
un volcado de la sesión, `log.bin`).

En pantalla ese contador avanzaba **un número cada ~2 segundos**.

    76 bytes / 2 s  =  ~38 bytes por segundo
                    =  ~26 ms por carácter

## Lo que ya está descartado

**No es el pintado del terminal.** 26 ms a 3,25 MHz son 85.000 ciclos por
carácter. Pintar un carácter en el ZX81 cuesta del orden de cientos de
ciclos, no decenas de miles. (Aun así se optimizó por el camino una
multiplicación por sumas repetidas que costaba ~2500 ciclos por carácter;
mejoró el terminal, pero no movió la aguja en esto.)

**No es el coste del comando MCU.** Se midió con un programa (`NETTIME.COM`,
fuente en `nettime.z80`) que lanza comandos `NET_READ` con `max=0` —el
"¿hay algo?" barato de la especificación, que no transfiere datos— y cuenta
cuántos caben en 5 segundos:

    8.192 comandos en 5 s  =  ~1.640 comandos/s  =  ~610 us por comando

Es decir, aun en el peor caso imaginable —un comando MCU por cada byte
recibido— el techo serían 1.640 bytes/s. Vemos 38.

**No es el disco compitiendo ni nada parecido.** Durante la medida no hay
actividad de SD.

## Lo que hace el lado Z80

El driver (`net.z80`) tiene un búfer de entrada de 128 bytes:

- `net_fill` solo lanza un comando **cuando ese búfer está vacío**, y
  siempre pide `max=128`.
- Mientras quede algo en el búfer, no se molesta al MCU.
- O sea: en el mejor caso, **un comando por cada 128 bytes**; en el peor
  (datos llegando a cuentagotas), un comando por cada uno o dos bytes.

El terminal consume un byte por vuelta de bucle y entre vuelta y vuelta
hace 3-4 llamadas al BDOS (con cambio de banco). Estimando 1 ms por
llamada, que es generoso, salen unos 5 ms por carácter, o sea del orden de
**200 bytes/s como suelo del lado Z80**. Sigue sin explicar los 38.

## Las preguntas

Por eliminación, el sospechoso es el ritmo al que el emulador **pone los
bytes a disposición** del Z80:

1. Con `max=128`, ¿qué `count` devuelve `NET_READ` cuando el socket tiene
   datos disponibles? ¿Todo lo que haya, o hay un tope pequeño (1, 4, 16…)?

2. ¿Hay un temporizador entre lecturas del socket? La especificación
   (`net_bridge_emulator.md`) pide explícitamente *"latencia no nula… el
   ritmo del sondeo del ESP32 (~15 ms con conexión abierta)"*. Si eso se
   implementó como "un sondeo cada 15 ms", está bien; pero si además cada
   sondeo entrega pocos bytes, los dos efectos se multiplican.

   Con 15 ms y 128 bytes por sondeo saldrían 8.500 B/s. Para quedarse en 38
   B/s haría falta que cada sondeo entregara **medio byte**.

3. ¿Hay alguna emulación de velocidad de línea (baudios)? 38 B/s son unos
   380 baudios, sospechosamente cerca de los 300 de un módem antiguo.

## Cómo reproducirlo

1. En CP/M: `DEVICE AUX:=NET`, luego `TERM LOG.BIN`.
2. Marcar con `ATDT <bbs>:<puerto>` (con `ENTER`+9 se enciende el eco local
   para ver lo que se teclea).
3. Cualquier pantalla ANSI con animación sirve de cronómetro.

`NETTIME.COM` no necesita conexión: mide solo el coste del comando.
