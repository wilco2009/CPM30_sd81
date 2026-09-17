; =====================================================================
;  memmap.inc - constantes del mapa de memoria banked compartidas entre
;  bank.z80, diskio.z80 y el resto del XIOS. Ver memory_map.md para la
;  justificacion completa de cada valor.
; =====================================================================

BANK0_BASE   equ 0    ; pagina fisica del banco 0 en el contexto sistema
BANK1_BASE   equ 8    ; pagina fisica del banco 0 en el contexto usuario
                       ; (la 7 la ocupa la zona comun, fija)

WINBLK       equ 3    ; bloque usado como VENTANA temporal (map1blk): el
                       ; driver del disco RAM y el relleno de HALT de la
                       ; pagina cero. No reside nada aqui -- se reprograma
                       ; el mapeo, se copian 128 B y se deja como estaba,
                       ; todo dentro de una misma llamada al BIOS. El unico
                       ; requisito es que no se ejecute nada desde este
                       ; bloque mientras la ventana esta abierta.
                       ;
                       ; Era el 6, y tuvo que cambiar al mudarse ahi la zona
                       ; duplicada (SWITCHER_BASE): map1blk vive DENTRO de
                       ; esa zona, o sea en el bloque 6, y no puede estar en
                       ; el bloque que esta reprogramando. Tampoco vale el 4,
                       ; donde esta el driver. El 3 quedo libre justo al
                       ; hacer esa mudanza.

RAMDISK_BASE equ 15   ; primera pagina fisica del pool del disco RAM
                       ; (paginas 15-63, 49 en total)

; ---------------------------------------------------------------------
;  Cargador de transitorios (loader.z80). Ocupa la ultima pagina del
;  TPA, en el banco de usuario, y es a la vez:
;    - el techo del TPA (@MXTPA)
;    - la entrada de la cadena BDOS ($0005 salta aqui)
;    - "bdosbase" del SCB, de donde la CCP saca la pila del transitorio
;      (baja desde LDR_BASE) y la direccion del FCB ($DEC0).
;  Ver la nota larga en loader.z80 y memory_map.md.
; ---------------------------------------------------------------------
; Crecio de 256 a 768 bytes al anadir el soporte de .COM con prefijo RSX:
; leer la cabecera, cargar el cuerpo, y (etapa 2) reubicar y encadenar los
; modulos. bios$tbl se queda donde estaba, en $DD80, asi que al stub le
; quedan los 640 bytes de $DA00-$DC7F.
; CPM3_SD81 (fase 1 del realineado DRI, ver layout_dri.md): bajado de
; $DA00 a $D200 para hacer sitio a la fuente, que se fue del banco 7 al
; banco de usuario. El cargador tiene que seguir siendo LO PRIMERO por
; encima del TPA: $0006 es a la vez el techo del TPA y la entrada a la
; BDOS, asi que todo lo demas que haya que proteger va ENCIMA de el.
LDR_BASE     equ 0D300h   ; direccion de ejecucion, en el banco de usuario
LDR_LEN      equ 512      ; multiplo de 128: ldccp_real copia por bloques
; CPM3_SD81 (fase 2): 768 -> 512 al irse bios$tbl al banco 7. El stub son
; 393 bytes; 512 es el siguiente multiplo de 128, y LDR_BASE sube de
; $D200 a $D300 -- el cargador sigue pegado a la zona duplicada
; ($D300+512 = $D500) y la TPA recupera 256 bytes.

; Tabla de saltos del BIOS que ven los programas, en la segunda mitad de
; esa misma pagina. 33 entradas de 3 bytes ($DD80-$DDE2). Se expresa
; como desplazamiento para que no se mueva si LDR_BASE cambia. $0001 apunta a
; su entrada WBOOT (BIOSTBL+3), que es de donde un programa de CP/M 2.2
; deduce la base del BIOS. Ver la nota larga en loader.z80.
; CPM3_SD81 (fase 2): $FF00, que es literalmente el "bios$pg" de DRI
; (RESBDOS.ASM:38, base+0FF00h: la ULTIMA pagina de la memoria comun).
; Estaba dentro de la pagina del cargador, en el banco de USUARIO, y por
; eso tenia que existir duplicada; aqui existe una sola vez y la ven los
; dos bancos por construccion. Ver layout_dri.md.
BIOSTBL      equ 0FF00h

; ---------------------------------------------------------------------
;  disk_handle - handles SD de las unidades A-D (4 bytes). EN BANCO
;  COMUN a proposito, y no en diskio.z80 con el resto del driver: asi
;  MOUNT3.COM puede escribirlos desde el TPA para montar otra imagen sin
;  reiniciar. En el banco de sistema serian inalcanzables para un
;  programa de usuario. Ver la nota de sd_login en diskio.z80.
;
;  Van justo detras de lstack, en la reserva de la tabla de fuentes
;  (glifos 24-31): lstack es el TOPE de la pila y crece hacia abajo, asi
;  que en $F8FC y siguientes no escribe nunca.
; ---------------------------------------------------------------------
DISKHANDLE   equ 0F8FCh

; ---------------------------------------------------------------------
;  Zona duplicada del conmutador de bancos (bank.z80). Existe byte a byte
;  en los dos contextos: la imagen la deja en la pagina de sistema y
;  dup_switcher la copia a la de usuario en el arranque.
;
;  ESTABA EN $7E00, o sea EN MITAD DEL TPA, y nada la protegia: @MXTPA
;  decia que el TPA llegaba mucho mas arriba, asi que para cualquier
;  programa esos 512 bytes eran memoria libre. Turbo Pascal cargaba sus
;  mensajes justo encima y destrozaba el conmutador -- ver memory_map.md.
;
;  Ahora va pegada al cargador, por encima de @MXTPA. Y el cargador queda
;  DEBAJO a proposito: $0006 es a la vez la entrada a la BDOS y el techo
;  del TPA que leen los programas, asi que todo lo que haya que proteger
;  tiene que estar por encima de LDR_BASE.
;
;    $D200-$D4FF   cargador + bios$tbl   (LDR_BASE, 768 B)
;    $D500-$D7FF   zona duplicada        (SWITCHER_BASE, 768 B)
;    $D800-$DFFF   fuente                (FONT_ADDR, 2048 B)
; ---------------------------------------------------------------------
; CPM3_SD81: movida de $DD00 a $D500. La fuente necesita $D800-$DFFF --
; el modo de 256 caracteres exige alineacion a 2 KB (SD81.v:1089 solo usa
; ROMTABLE[15:11]), asi que $D800 es la unica base que encaja aqui, y se
; comia el sitio de la zona duplicada. Sigue en el bloque 6, que es lo
; unico que importa: SWITCHER_OFF se deriva sola.
SWITCHER_BASE equ 0D500h
SWITCHER_LEN  equ 0300h
SWITCHER_BLK  equ 6           ; bloque que la contiene ($C000-$DFFF)

; ---------------------------------------------------------------------
;  Vectores de asignacion (ALV) de las unidades. Van AQUI, detras de la
;  imagen de la CCP, y no en diskio.z80 con el resto del driver: con el
;  formato de 2 MB pasan de 63 a 257 bytes por unidad ((DSM/4)+2 con
;  DSM=1023, doble bit) y no caben en el hueco del XIOS, que tiene que
;  terminar antes de $8A00.
;
;  CPM3_SD81: estaba en $C800, en el banco de SISTEMA, y por eso la
;  funcion 27 (Get Allocation Vector Address) quedo rota a proposito:
;  devolvia una direccion correcta a la que el programa que preguntaba no
;  podia llegar. La excusa era que son 1042 bytes y "no caben en comun ni
;  de lejos", lo cual era cierto con el banco 7 lleno al 100%.
;
;  Dejo de serlo con el realineado DRI: al subir el BDOS residente a
;  $F931 quedaron 1382 bytes contiguos libres en $F032 (comprobado: ni un
;  simbolo ni un equ apuntan ahi). El ALV cabe con 340 de sobra, asi que
;  se muda a comun y la funcion 27 pasa a devolver algo util.
;
;  No cuesta TPA: el banco 7 es memoria comun. Y de paso libera 1042
;  bytes del banco de sistema, donde estaba entre la imagen de la CCP y
;  BKIOEXT.
;
;  El espacio se reserva en system.z80, detras del include de
;  RESBDOS.ASM, con guarda contra el BIOS ($F598).
;
;  No hace falta CSV: el DPB declara el medio como fijo (CKS=8000h), asi
;  que no hay vector de checksum. Se puede porque la unica forma de
;  cambiar una imagen es MOUNT3, que hace un reset de unidad.
; ---------------------------------------------------------------------
ALV_BASE     equ 0F032h   ; banco 7, en el hueco que dejo el RESBDOS
ALV_SD       equ 257      ; (DSM/4)+2 con DSM=1023  -- unidades A-D
ALV_RAM      equ 14       ; (DSM/4)+2 con DSM=48    -- unidad E

; ---------------------------------------------------------------------
;  DPB de las unidades. EN BANCO COMUN, y esto NO es opcional.
;
;  La funcion 31 de la BDOS (get disk parameter address) devuelve al
;  programa la direccion del DPB tal cual. Si el DPB vive en el banco de
;  sistema -- donde estaba, en $8202 -- el programa la dereferencia desde
;  el banco de usuario y lee TPA. Sintoma: "DIR fichero [FULL]" daba
;  tamanos al tuntun (PIP.COM, 10K reales, salia como 20K) y "Max Dir
;  Entries" salia "H942", que ni siquiera es un numero.
;
;  Van en el hueco que dejaba la guarda del bloque de banco 7 de init.z80
;  ($F775-$F7A3, 47 bytes): 17+17 = 34, con 13 de sobra. Son datos de
;  SOLO LECTURA, asi que no hay problema de duplicacion.
;
;  El comentario de drvtbl.z80 decia que los XDPH/DPB "pueden vivir en
;  banco comun o en sistema indistintamente". Es falso, y esta es la
;  demostracion.
; ---------------------------------------------------------------------
; OJO con el nombre: zmac NO distingue mayusculas de minusculas, asi que
; DPB_SD chocaria con la etiqueta dpb_sd: de drvtbl.z80 (misma trampa que
; BIOSTBL/bios$tbl). Solo hace falta la direccion base.
DPBORG       equ 0F775h   ; dpb_sd y dpb_ram, 17 bytes cada uno

; ---------------------------------------------------------------------
;  Bloque de E/S de caracter de BIOSKRNL, FUERA del banco 7.
;
;  DRI lo puso en "cseg" (memoria comun) para que un programa pudiera
;  llamar al BIOS directamente sin cambiar de banco. Esa premisa dejo de
;  aplicar el dia que metimos "biosw" delante de cada entrada de la
;  tabla: el envoltorio YA selecciona sistema antes de saltar al cuerpo y
;  restaura el banco del llamante al volver. O sea que el cuerpo llevaba
;  tiempo sin necesitar ser comun -- solo lo parecia.
;
;  Son 248 bytes de banco 7 recuperados: devtbl, getdrv, conout, auxout,
;  list, const, conin, auxin, conost, auxost, listst, auxist, los cuatro
;  *$scan con sus *$next, y coster + xofflist.
;
;  Se queda en comun lo que de verdad lo necesita: boot$1, wboot,
;  set$jumps (selecciona usuario en mitad de su ejecucion), boot$stack y
;  bnksel.
;
;  Va detras de los ALV. La guarda de system.z80 para en BKIOEXT para no
;  rellenarle encima, y la de aqui cierra hasta LDR_BASE.
; ---------------------------------------------------------------------
BKIOEXT      equ 0CC80h   ; detras de los ALV ($C800 + 1042 = $CC12)

; ---------------------------------------------------------------------
;  @dtbl y los XDPH/DPH, en el hueco que deja la E/S de caracter al
;  mudarse (BKIOEXT). Tienen que ser comunes:
;
;    - BIOS SELDSK (entrada 9) devuelve al programa la direccion del DPH.
;      Es como un programa de CP/M 2.2 llega al DPB, al ALV y al CSV.
;    - BIOS DRVTBL (entrada 22) devuelve la de @dtbl.
;
;  Y a diferencia del DPB, el DPH NO es de solo lectura: tiene 9 bytes de
;  scratch y el byte MF que escribe la BDOS. Asi que no vale con que este
;  "duplicado e identico" -- tiene que ser comun de verdad, una sola
;  copia. De ahi que hiciera falta liberar banco 7 y no bastara con la
;  pagina del cargador.
;
;  207 bytes: 32 de @dtbl + 5 XDPH de 35.
;
;  Guardas a los dos lados: BIOSKRNL cierra su bloque comun con
;  "ds DTBLORG-$" y este bloque con "ds 0F704h-$", que es donde empieza
;  ldccp_real (init.z80).
; ---------------------------------------------------------------------
DTBLORG      equ 0F618h

; ---------------------------------------------------------------------
;  @ctbl -- la tabla de dispositivos de caracter, EN BANCO COMUN.
;
;  BIOS DEVTBL (entrada 20) devuelve su direccion al programa. Estaba en
;  chario.z80, o sea en $835C del banco de sistema, y DEVICE.COM la leia
;  desde el banco de usuario: donde tenia que salir "CON" salia "6$", y
;  algun $1A de la basura hacia que ?co borrara la pantalla.
;
;  Mismo fallo que el DPB, el DPH y @dtbl. En la auditoria anterior se
;  dio por bueno porque la RUTINA "devtbl" estaba en comun -- pero lo que
;  el programa lee no es la rutina, es la TABLA que devuelve.
;
;  Con dos dispositivos (CON y NET, ver net.z80) son 17 bytes: 8 por
;  dispositivo (6 de nombre + modo + baudios) mas el terminador. Ya no
;  caben en los 9 bytes que quedaban detras de los DPB, asi que pasa al
;  hueco de 29 que hay detras de los DPH ($F6E7-$F703). De rebote, los
;  DPB pasan a rellenar hasta BD_RT en lugar de hasta aqui.
; ---------------------------------------------------------------------
CTBLORG      equ 0F6E7h

; ---------------------------------------------------------------------
;  rtc.z80, fuera del hueco apretado del XIOS.
;
;  El tramo $8000-$89FF (entre BIOSKRNL y el "org 08A00h" de BDOS.ASM) ya
;  iba al limite, y el reloj son unos 450 bytes. Va detras del bloque de
;  E/S de caracter (BKIOEXT), en el mismo banco de sistema.
;
;  Guardas encadenadas: BIOSKRNL cierra su bloque con "ds RTCORG-$" y
;  este con "ds LDR_BASE-$", asi que ningun "ds" rellena encima del
;  siguiente.
; ---------------------------------------------------------------------
RTCORG       equ 0CE00h

; ---------------------------------------------------------------------
;  net.z80, por el mismo motivo que el reloj: no cabe en el tramo
;  $8000-$89FF. Son unos 420 bytes, y 256 de ellos son los dos buferes
;  de 128 -- el precio de no hacer un comando MCU por cada caracter.
;
;  Va detras del reloj, en los 727 bytes que quedaban entre el final de
;  rtc.z80 ($D029) y el cargador. Guardas encadenadas: rtc cierra con
;  "ds NETORG-$" y net.z80 con "ds LDR_BASE-$".
; ---------------------------------------------------------------------
NETORG       equ 0D030h

; ---------------------------------------------------------------------
;  Las ampliaciones del terminal ANSI (ESC[s, ESC[u y la respuesta al
;  ESC[6n), por el mismo motivo de siempre: el XIOS no cabe en el tramo
;  $8000-$89FF. Con esto se paso por 102 bytes.
;
;  Va detras de net.z80, en lo que quedaba antes del cargador. Guardas
;  encadenadas: net.z80 cierra con "ds ANSIORG-$" y este bloque con
;  "ds LDR_BASE-$".
; ---------------------------------------------------------------------
ANSIORG      equ 0D210h

; ---------------------------------------------------------------------
;  Estado de biosd (bank.z80), el envoltorio de las entradas de disco.
;  Cuatro bytes, en el hueco que quedaba detras de @ctbl.
;
;  Son SUYOS y no compartidos con biosw a proposito: la BDOS puede estar
;  en mitad de una operacion de disco y tener que imprimir un error, y
;  entonces conout entra por biosw. Con variables compartidas se
;  pisarian.
;
;  No hace falta guardar HL: ?bank preserva todos los registros desde que
;  se arreglo. biosw todavia tiene su bw$hl porque se escribio antes de
;  aquello, y se queda como esta para no tocar lo que ya funciona.
; ---------------------------------------------------------------------
; OJO con el reparto: no todas pueden vivir en el mismo sitio. Depende de
; en que banco se escribe cada una y en cual se lee:
;
;   bd$sp   se escribe y se lee en el banco del LLAMANTE (el "ld sp"
;           de vuelta va despues de restaurarlo) -> le vale la ZONA
;           DUPLICADA, y por eso vive alli (bank.z80) en vez de aqui.
;   BD_RT   se escribe en el banco del llamante y se lee bajo sistema.
;   BD_A    se escribe bajo sistema y se lee en el del llamante.
;
; Las dos ultimas cruzan el cambio de banco, asi que tienen que ser
; comunes de verdad -- una sola copia.
BD_RT        equ 0F7A0h   ; direccion de la rutina real (2 B)
BD_BNK       equ 0F7A2h   ; banco del llamante, para restaurarlo
BD_A         equ 0F7A3h   ; valor devuelto en A


; ---------------------------------------------------------------------
;  SCB_PAGE - la pagina del SCB. Es "scb$pg" de DRI (RESBDOS.ASM:37,
;  base+0FE00h) y de ella cuelga todo lo demas:
;
;    scb$pg+68h   los thunks parcheables (wbootfx...), donde SAVE.COM
;                 mete un $21 sobre el $C3 para desviar la E/S de
;                 consola del BIOS directo al camino bancado
;    scb$pg+90h   olog: aqui EMPIEZA el SCB, y por tanto aqui tiene que
;                 TERMINAR el BDOS residente (lo verifica la guarda del
;                 final de RESBDOS.ASM)
;    scb$pg+9Ch   el SCB publico (scb$base)
;    scb$pg+100h  bios$pg = BIOSTBL
;
;  Tiene que estar alineada a pagina: SAVE calcula la direccion del
;  thunk como (scbadd & $FF00) + 68h.
;
;  Lo definia BDOS.ASM ($E000) y SCB.ASM repetia la base a pelo ($E09C).
;  Ahora sale de aqui y los dos la derivan.
; ---------------------------------------------------------------------
SCB_PAGE     equ 0FE00h


; ---------------------------------------------------------------------
;  Configuracion de la FPGA (video y modo). Estaba en init.z80, pero
;  TODA la configuracion inicial de la FPGA se hace ahora en "start:"
;  (system.z80), y start: se ensambla ANTES que init.z80 -- asi que los
;  equates tienen que vivir aqui, que es lo primero que se incluye.
; ---------------------------------------------------------------------
DFILE_OVR      equ 2096
DFILE_OVR_EN   equ 2098
DFILE_val      equ 0E899h
ATTR_OVR       equ 2059
ATTR_OVR_EN    equ 2061
ATTR_val       equ 0E100h
ATTR_SCREEN    equ 01Eh        ; papel azul ($1), tinta amarilla brillante
CHROMA_PORT    equ 07FEFh      ; registro de modo Chroma (SD81.v:427)
CHROMA_val     equ 031h        ; color_enable + color_mode + borde azul
FONT_I         equ 0D8h
FONT_ADDR      equ 0D800h        ; la tabla la genera font_image.z80
ROWS           equ 24
COLS           equ 80
DataPort       equ 0A7h
ClkPort        equ 0AFh
CMD_chars256   equ 041h        ; SEL_256CHARS = 65
CMD_fullpaging equ 01Dh        ; 29
