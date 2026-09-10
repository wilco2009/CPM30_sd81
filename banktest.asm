; =====================================================================
;  banktest.asm - CP/M+ SD81Booster: primer test en hardware real de
;  FULL_PAGING, ?bank (aislamiento sistema/usuario) y map1blk (ventana de
;  una pagina, usada por el driver del disco RAM). Standalone, sin
;  BDOS/CCP/GENCPM -- reutiliza el video ya validado en CPM_SD81
;  (boot_cpm.asm / sel256chars_test.asm) para imprimir resultados.
;
;  TERMINOLOGIA (ver memory_map.md): "banco" = cada uno de los 8 trozos
;  de 8K del espacio Z80 (0-7, hardware puro). "pagina" = cada uno de los
;  64 trozos de 8K de los 512K de RAM fisica. "sistema"/"usuario" = los
;  dos contextos logicos de CP/M 3 (lo que DRI llama "bank" en ingles;
;  evitamos aqui la palabra "banco" para esto y usamos "?bank" solo como
;  nombre de la rutina, tal cual la llama BIOSKRNL.ASM).
;
;  POR QUE ESTA DUPLICADO EL SWITCHER (IMPORTANTE):
;  ?bank reprograma los bancos Z80 0-6 con las paginas del contexto
;  elegido. El banco 7 no puede ejecutar codigo sin el mod MC45 (cae en
;  A15=1), asi que el switcher (?bank/map1blk) no puede vivir ahi como en
;  un diseño "comun = banco alto" clasico -- vive al FINAL del banco 3
;  ($7E00-$7FFF, A15=0, seguro sin MC45), duplicado byte a byte en la
;  pagina de sistema (3) y la pagina de usuario (11) para esa misma
;  direccion. Ademas, CUALQUIER codigo que siga ejecutandose justo
;  despues de un cambio de contexto (sin volver antes a sistema) tiene
;  que vivir tambien ahi duplicado -- por eso test_bank/test_ramdisk
;  estan en la misma zona duplicada, no en el arranque a $6000. La regla
;  real (la que seguira el BIOSKRNL de verdad): un cambio de contexto
;  debe ser lo ULTIMO que hace una rutina antes de devolver el control a
;  codigo que sea valido en el contexto NUEVO -- nunca "cambiar y seguir
;  ejecutando mas codigo sin duplicar".
;
;  Ensamblar: zmac --od . --oo cim banktest.asm
;  Cargar (desde BASIC):
;    LOAD THEN CLEAR 24575
;    LOAD FAST "BANKTEST.BIN" CODE 24576
;    RAND USR 24576
; =====================================================================

DFILE_OVR      equ 2096
DFILE_OVR_EN   equ 2098
DFILE_val      equ 0EA00h
ATTR_OVR       equ 2059
ATTR_OVR_EN    equ 2061
ATTR_val       equ 0E200h      ; libre, antes de DFILE_val ($EA00)
FONT_I         equ 0F8h
FONT_ADDR      equ 0F800h
CHARSET_SRC    equ 01E00h

ROWS           equ 24
COLS           equ 80

DataPort       equ 0A7h
ClkPort        equ 0AFh
CMD_chars256   equ 041h        ; SEL_256CHARS = 65
CMD_fullpaging equ 01Dh        ; 29

BANK0_BASE     equ 0           ; pagina del banco 0 en el contexto sistema
BANK1_BASE     equ 8           ; pagina del banco 0 en el contexto usuario
                                ; (7 esta ocupada por la zona comun)
WINBLK         equ 6           ; banco usado como ventana por test_ramdisk
DUPWIN         equ 5           ; banco usado como ventana para duplicar
                                ; el switcher en el arranque
RAMDISK_BASE   equ 15

; codigos de caracter ZX81 (NO ASCII): la fuente cargada es una copia
; directa de la ROM ($1E00), en el orden nativo del ZX81, no en orden
; ASCII -- escribir bytes ASCII en pantalla (p.ej. 'A'=65) muestra el
; glifo que haya en esa posicion del charset ZX81, no una "A". Tabla:
; 0=espacio, 28-37=digitos '0'-'9', 38-63=letras 'A'-'Z'.
ZX_SPACE       equ 0
ZX_DIGIT0      equ 28
ZX_A           equ 38
ZX_END         equ 0FFh        ; terminador de mensaje (0 ya es "espacio")

SWITCHER_BASE  equ 07E00h      ; banco 3, ultimos 512 B ($7E00-$7FFF)
SWITCHER_LEN   equ 0200h
BANK3_ADDR     equ 06000h      ; direccion Z80 base del banco 3
SWITCHER_OFF   equ SWITCHER_BASE-BANK3_ADDR    ; offset dentro de la pagina
DUPWIN_ADDR    equ 0A000h      ; direccion Z80 base del banco DUPWIN

            org  06000h

boot_start:
            di
            ld   sp, 0F7FFh
            xor  a
            out  (0FDh), a      ; NMI off

            ld   a, FONT_I
            ld   i, a

            ; fuente: copia de ROM x4 (metodo probado en sel256chars_test.asm).
            ; TIENE que ir aqui, ANTES del remapeo de bloques de abajo: $1E00
            ; esta en el bloque 0, que solo es la ROM real hasta que las tres
            ; OUT (0E7h),A siguientes lo remapean a la pagina 8 (RAM vacia) --
            ; mismo bug/orden que ya documentamos y corregimos en
            ; boot_cpm_test.asm; se me olvido trasladarlo aqui.
            ld   de, FONT_ADDR
            ld   b, 4
copy_font:  push bc
            ld   hl, CHARSET_SRC
            ld   bc, 512
            ldir
            pop  bc
            djnz copy_font

            ; secuencia de video real de boot_cpm.asm (ya validada en hardware)
            ld   a, (8 << 3)  | 0
            out  (0E7h), a
            ld   a, (9 << 3)  | 1
            out  (0E7h), a
            ld   a, (10 << 3) | 2
            out  (0E7h), a

            ld   hl, DFILE_val
            ld   (DFILE_OVR), hl
            ld   a, 170
            ld   (DFILE_OVR_EN), a

            ld   hl, ATTR_val
            ld   (ATTR_OVR), hl
            ld   a, 170
            ld   (ATTR_OVR_EN), a

            ld   a, 174
            ld   (2045), a

            xor  a
            ld   (2094), a
            ld   (2095), a

            ld   (2056), a

            ld   a, CMD_chars256
            call mcu_send

            call clear_screen
            call clear_attrs

            ; --- activar FULL_PAGING antes de tocar ?bank/map1blk ---
            ld   a, CMD_fullpaging
            call mcu_send

            ; --- duplicar el switcher (banco 3) en la pagina de usuario ---
            call dup_switcher

            ; --- test 1: ?bank aisla los contextos sistema/usuario ---
            ld   hl, msg_t1
            call print_msg
            call test_bank
            call print_result

            ; --- test 2: disco RAM (map1blk alcanza pagina fisica real) ---
            ld   hl, msg_t2
            call print_msg
            call test_ramdisk
            call print_result

hang:       jp   hang

; ---------------------------------------------------------------------
; mcu_send - protocolo MCU de bajo nivel (igual que sel256chars_test.asm)
; A = byte/comando a enviar. B queda usado como scratch.
; ---------------------------------------------------------------------
mcu_send:   ld   b,a
            in   a,(ClkPort)
            ld   c,a
            ld   a,b
            out  (DataPort),a
            ld   a,c
            cpl
            ld   c,a
ms_wait:    in   a,(ClkPort)
            xor  c
            jp   m, ms_wait
            ret

; ---------------------------------------------------------------------
; clear_screen - pone toda la pantalla a espacios (codigo 0)
; ---------------------------------------------------------------------
clear_screen:
            ld   hl, DFILE_val+1
            ld   b, ROWS
cls_row:    push bc
            ld   c, COLS
            xor  a
cls_col:    ld   (hl), a
            inc  hl
            dec  c
            jr   nz, cls_col
            ld   (hl), 0
            inc  hl
            pop  bc
            djnz cls_row
            ret

; ---------------------------------------------------------------------
; clear_attrs - rellena ATTR_val con tinta blanca / papel negro. Formato
; real de los modos anchos (superfast_wide_text_modes.md #5): nibble alto
; = PAPEL, nibble bajo = TINTA (NO el 3+3 estilo Spectrum) -- $0F =
; papel=0 (negro), tinta=$F. Sin esto, con el override de atributos
; activo pero sin rellenar, el atributo por defecto (0 = tinta y papel
; ambos a 0) deja el texto invisible aunque los caracteres se dibujen
; bien.
; ---------------------------------------------------------------------
clear_attrs:
            ld   hl, ATTR_val+1
            ld   b, ROWS
cla_row:    push bc
            ld   c, COLS
            ld   a, 0Fh
cla_col:    ld   (hl), a
            inc  hl
            dec  c
            jr   nz, cla_col
            ld   (hl), 0
            inc  hl
            pop  bc
            djnz cla_row
            ret

; ---------------------------------------------------------------------
; dup_switcher - copia los SWITCHER_LEN bytes en SWITCHER_BASE (ya
; cargados con el resto del programa, en la pagina de sistema = 3) a la
; misma direccion relativa dentro de la pagina de usuario para el banco 3
; (pagina 11), usando el banco DUPWIN como ventana temporal. OJO: hay que
; escribir en DUPWIN_ADDR+SWITCHER_OFF, no en DUPWIN_ADDR -- si no, la
; copia queda en el offset equivocado de la pagina y el truco falla en
; cuanto el banco 3 pase a mostrar la pagina de usuario.
; ---------------------------------------------------------------------
dup_switcher:
            ld   a, BANK1_BASE+3
            ld   e, DUPWIN
            call map1blk
            ld   hl, SWITCHER_BASE
            ld   de, DUPWIN_ADDR+SWITCHER_OFF
            ld   bc, SWITCHER_LEN
            ldir
            ld   a, BANK0_BASE+DUPWIN
            ld   e, DUPWIN
            call map1blk
            ret

; ---------------------------------------------------------------------
; print_msg - imprime el mensaje en HL (terminado en ZX_END=$FF, no en 0
; -- 0 es un codigo de caracter valido, el espacio) en la fila cur_prow,
; columna 0.
; ---------------------------------------------------------------------
cur_prow:   db   0

print_msg:  push hl
            ld   a,(cur_prow)
            call row_addr
            pop  de
pm_loop:    ld   a,(de)
            cp   ZX_END
            jr   z, pm_done
            ld   (hl), a
            inc  hl
            inc  de
            jr   pm_loop
pm_done:    ret

; ---------------------------------------------------------------------
; row_addr - HL = DFILE_val+1 + A*(COLS+1), A = fila (0-23)
; ---------------------------------------------------------------------
row_addr:   ld   hl, DFILE_val+1
            or   a
            ret  z
            ld   b, a
ra_loop:    push bc
            ld   bc, COLS+1
            add  hl, bc
            pop  bc
            djnz ra_loop
            ret

; ---------------------------------------------------------------------
; print_result - imprime "OK" (Z) o "FAIL gggg" (NZ, gggg = test_got en
; hex, 16 bits) en la columna 20 de cur_prow, y avanza cur_prow.
; ---------------------------------------------------------------------
print_result:
            push af
            ld   a,(cur_prow)
            call row_addr
            ld   de,20
            add  hl,de
            pop  af
            jr   z, pr_ok
            ld   (hl),ZX_A+5        ; 'F'
            inc  hl
            ld   (hl),ZX_A          ; 'A'
            inc  hl
            ld   (hl),ZX_A+8        ; 'I'
            inc  hl
            ld   (hl),ZX_A+11       ; 'L'
            inc  hl
            ld   (hl),ZX_SPACE
            inc  hl
            ld   a,(test_got+1)   ; byte alto primero
            call print_hex
            ld   a,(test_got)
            call print_hex
            jr   pr_done
pr_ok:      ld   (hl),ZX_A+14       ; 'O'
            inc  hl
            ld   (hl),ZX_A+10       ; 'K'
            inc  hl
pr_done:    ld   a,(cur_prow)
            inc  a
            ld   (cur_prow),a
            ret

; ---------------------------------------------------------------------
; print_hex - imprime el byte A en hex en (HL), avanza HL 2 posiciones
; ---------------------------------------------------------------------
print_hex:  push af
            rrca
            rrca
            rrca
            rrca
            call ph_nib
            pop  af
ph_nib:     and  0Fh
            cp   10
            jr   c, ph_digit
            add  a,ZX_A-10          ; 'A'-'F'
            jr   ph_out
ph_digit:   add  a,ZX_DIGIT0        ; '0'-'9'
ph_out:     ld   (hl),a
            inc  hl
            ret

; "TEST BANCOS" / "TEST DISCO RAM" en codigos ZX81 (ver ZX_SPACE/ZX_A
; arriba), terminados en ZX_END, no en ASCII.
msg_t1:     db   57,42,56,57,0,39,38,51,40,52,56,ZX_END
msg_t2:     db   57,42,56,57,0,41,46,56,40,52,0,55,38,50,ZX_END

; test_got no necesita ir en zona duplicada ni en el banco 7: solo se lee
; y escribe con el contexto sistema ya activo (justo antes de que
; test_bank/test_ramdisk devuelvan el control), asi que le vale
; perfectamente vivir aqui, en la seccion normal del banco 3.
test_got:   dw   0

; =======================================================================
;  Switcher duplicado -- banco 3, $7E00-$7FFF (512 B). Todo lo de aqui
;  abajo se copia tambien a la pagina de usuario (11) por dup_switcher,
;  arriba. Nada de fuera de esta zona debe seguir ejecutandose despues de
;  un ?bank que cambie de contexto sin haber vuelto antes a sistema.
; =======================================================================

            org  SWITCHER_BASE

; ---------------------------------------------------------------------
; map1blk - mapea la pagina A en el banco E (0-7). No toca @cbnk ni el
; resto de bancos.
; ---------------------------------------------------------------------
map1blk:    push bc
            ld   b,a
            ld   c,0E7h
            ld   a,e
            out  (c),a
            pop  bc
            ret

; ---------------------------------------------------------------------
; ?bank - selecciona contexto de ejecucion. A = 0 (sistema) o 1 (usuario).
; Reprograma los bancos 0-6 (el 7, comun, no se toca).
; ---------------------------------------------------------------------
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
            add  a,c
            ld   b,a
            push bc
            ld   a,c
            ld   c,0E7h
            out  (c),a
            pop  bc
            inc  c
            dec  e
            jr   nz, bank_loop
            pop  de
            pop  bc
            pop  af
            ret

; ---------------------------------------------------------------------
; test_bank - escribe $AA en sistema@0100h, cambia a usuario, escribe
; $55 en la misma direccion, vuelve a sistema y comprueba que sigue
; leyendose $AA (prueba que los TPA de sistema/usuario son fisicamente
; distintos). Devuelve Z si paso; si no, test_got = valor leido.
; ---------------------------------------------------------------------
test_bank:  xor  a
            call ?bank
            ld   a,0AAh
            ld   (0100h),a

            ld   a,1
            call ?bank
            ld   a,55h
            ld   (0100h),a

            xor  a
            call ?bank
            ld   a,(0100h)
            ld   h,0
            ld   l,a
            ld   (test_got),hl
            cp   0AAh
            ret

; ---------------------------------------------------------------------
; test_ramdisk - mapea el banco WINBLK sobre la primera pagina del disco
; RAM, escribe un patron reconocible, remapea ese mismo banco de vuelta
; a sistema (lo "pierde"), lo corrompe, vuelve a mapear la pagina del
; disco RAM y comprueba que el patron sigue ahi -- prueba que map1blk
; alcanza memoria fisica real e independiente del contexto sistema/
; usuario. Devuelve Z si paso; si no, test_got = valor leido.
; ---------------------------------------------------------------------
test_ramdisk:
            xor  a
            call ?bank              ; sistema conocido antes de empezar

            ld   a,RAMDISK_BASE
            ld   e,WINBLK
            call map1blk            ; ventana ($C000) -> disco RAM pagina 0
            ld   hl,0AA55h
            ld   (0C000h),hl        ; escribe el patron

            ld   a,BANK0_BASE+WINBLK
            ld   e,WINBLK
            call map1blk            ; ventana -> sistema de nuevo (se "olvida")
            ld   hl,0
            ld   (0C000h),hl        ; corrompe lo que hubiera ahi

            ld   a,RAMDISK_BASE
            ld   e,WINBLK
            call map1blk            ; vuelve a mapear la pagina del disco RAM
            ld   hl,(0C000h)
            ld   (test_got),hl

            ld   a,BANK0_BASE+WINBLK
            ld   e,WINBLK
            call map1blk            ; restaura definitivamente el banco 6

            ld   hl,(test_got)
            ld   a,l
            cp   55h
            ret  nz
            ld   a,h
            cp   0AAh
            ret

            end
