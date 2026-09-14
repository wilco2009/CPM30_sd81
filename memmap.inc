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
LDR_BASE     equ 0DA00h   ; direccion de ejecucion, en el banco de usuario
LDR_LEN      equ 768      ; multiplo de 128: ldccp_real copia por bloques

; Tabla de saltos del BIOS que ven los programas, en la segunda mitad de
; esa misma pagina. 33 entradas de 3 bytes ($DD80-$DDE2). Se expresa
; como desplazamiento para que no se mueva si LDR_BASE cambia. $0001 apunta a
; su entrada WBOOT (BIOSTBL+3), que es de donde un programa de CP/M 2.2
; deduce la base del BIOS. Ver la nota larga en loader.z80.
BIOSTBL      equ LDR_BASE+280h

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
;    $DA00-$DCFF   cargador + bios$tbl   (LDR_BASE, 768 B)
;    $DD00-$DFFF   zona duplicada        (SWITCHER_BASE, 768 B)
; ---------------------------------------------------------------------
SWITCHER_BASE equ 0DD00h
SWITCHER_LEN  equ 0300h
SWITCHER_BLK  equ 6           ; bloque que la contiene ($C000-$DFFF)

; ---------------------------------------------------------------------
;  Vectores de asignacion (ALV) de las unidades. Van AQUI, detras de la
;  imagen de la CCP, y no en diskio.z80 con el resto del driver: con el
;  formato de 2 MB pasan de 63 a 257 bytes por unidad ((DSM/4)+2 con
;  DSM=1023, doble bit) y no caben en el hueco del XIOS, que tiene que
;  terminar antes de $8A00.
;
;  El espacio se reserva en system.z80 justo detras de ccp_image.z80,
;  con guardas a los dos lados: una comprueba que la CCP no se pasa de
;  ALV_BASE y otra que los buffers no llegan al cargador (LDR_BASE).
;
;  No hace falta CSV: el DPB declara el medio como fijo (CKS=8000h), asi
;  que no hay vector de checksum. Se puede porque la unica forma de
;  cambiar una imagen es MOUNT3, que hace un reset de unidad.
; ---------------------------------------------------------------------
ALV_BASE     equ 0C800h   ; detras de la imagen de la CCP ($BD00-$C700),
                          ; con 256 B de holgura por si la CCP crece
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
;  Son 9 bytes (6 de nombre + modo + baudios + terminador) y de solo
;  lectura. Caben en el hueco que quedaba detras de los DPB.
; ---------------------------------------------------------------------
CTBLORG      equ 0F797h

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
BD_SP        equ 0F7A0h   ; SP del llamante
BD_BNK       equ 0F7A2h   ; su banco, para restaurarlo
BD_A         equ 0F7A3h   ; valor devuelto en A
