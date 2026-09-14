; =====================================================================
;  mount3.asm  -  MOUNT3.COM : monta un .img en una unidad CP/M (A-D)
;  sin reiniciar. Version para CP/M 3 (CPM3_SD81).
;
;  Sintaxis:  MOUNT3 d nombre.img       (ej:  MOUNT3 B GAMES.IMG)
;  Ensamblar con zmac (ORG $0100) -> MOUNT3.COM
;
;  El original para CP/M 2.2 sigue donde estaba, en CPM_SD81/mount.asm.
;  Aqui cambia UNA cosa, pero es la que lo hacia inservible: la
;  direccion de disk_handle[].
;
;    2.2    $E018   VARBASE+24, en la RAM dedicada del BIOS
;    CP/M 3 $F8FC   banco 7 (comun)
;
;  En CP/M 3 el driver de disco vive en el banco de SISTEMA, que un
;  programa de usuario no puede ni ver. Por eso disk_handle[] se saco a
;  la zona comun -- es alcanzable desde el TPA pase lo que pase con el
;  paginado. $E018, la direccion vieja, cae en CP/M 3 dentro de los
;  datos de la BDOS residente: escribir ahi no solo no montaba nada,
;  sino que corrompia el sistema.
;
;  Y hubo que tocar tambien el driver: sd_login reabria el .IMG en CADA
;  login, asi que el reset de unidad que hace este programa al final
;  (BDOS 37) machacaba el handle recien montado. Ahora solo abre si el
;  handle vale $FF. Ver diskio.z80.
;
;  Habla directo con el MCU del SD81 (puertos A7h/AFh), igual que el
;  original: eso no cambia, son instrucciones IN/OUT y funcionan desde
;  cualquier banco.
; =====================================================================

BDOS        equ 0005h
DataPort    equ 0A7h
ClkPort     equ 0AFh
DISKHANDLE  equ 0F8FCh          ; banco comun, ver memmap.inc del XIOS

            org 0100h

; --- parsear la cola de comando en $0080 (long) / $0081.. (texto) ---
            ld   a,(0080h)
            ld   c,a            ; C = bytes restantes
            ld   hl,0081h
ps_sp1:     ld   a,c
            or   a
            jp   z,usage
            ld   a,(hl)
            cp   ' '
            jr   nz,ps_drv
            inc  hl
            dec  c
            jr   ps_sp1
ps_drv:     and  0DFh           ; a mayuscula
            sub  'A'
            cp   4
            jp   nc,usage       ; unidad fuera de A-D
            ld   (drive),a
            inc  hl
            dec  c
ps_sp2:     ld   a,c
            or   a
            jp   z,usage        ; falta el nombre
            ld   a,(hl)
            cp   ' '
            jr   nz,ps_nm
            inc  hl
            dec  c
            jr   ps_sp2
ps_nm:      ld   de,namebuf     ; copiar nombre hasta espacio o fin
ps_cp:      ld   a,c
            or   a
            jr   z,ps_end
            ld   a,(hl)
            cp   ' '
            jr   z,ps_end
            ld   (de),a
            inc  hl
            inc  de
            dec  c
            jr   ps_cp
ps_end:     xor  a
            ld   (de),a         ; terminar nombre en 0

; --- cerrar el handle actual de la unidad ---
            ld   a,(drive)
            ld   e,a
            ld   d,0
            ld   hl,DISKHANDLE
            add  hl,de
            ld   (dhptr),hl
            ld   a,(hl)
            call sd_fclose

; --- abrir el nuevo .img ---
            ld   hl,namebuf
            call sd_fopen       ; A = handle (0FFh si error)
            cp   0FFh
            jp   z,err_open
            ld   hl,(dhptr)     ; guardar nuevo handle en disk_handle[drive]
            ld   (hl),a

; --- resetear la unidad para que el BDOS relea el directorio (func 37) ---
            ld   a,(drive)
            ld   e,1            ; mascara = 1 << drive
rs_sh:      or   a
            jr   z,rs_do
            sla  e
            dec  a
            jr   rs_sh
rs_do:      ld   d,0
            ld   c,37
            call BDOS

            ld   de,msgok
            jr   done
err_open:   ld   de,msgerr
            jr   done
usage:      ld   de,msguse
done:       ld   c,9
            call BDOS
            ret

; ---------------------------------------------------------------------
;  Protocolo MCU (igual que sddisk.z80): C = clock de referencia
; ---------------------------------------------------------------------
sd_clk:     in   a,(ClkPort)
            ld   c,a
            ret
mcu_send:   out  (DataPort),a
            ld   a,c
            cpl
            ld   c,a
ms_w:       in   a,(ClkPort)
            xor  c
            jp   m,ms_w
            ret
mcu_recv:   in   a,(DataPort)
            push af
            ld   a,c
            cpl
            ld   c,a
mr_w:       in   a,(ClkPort)
            xor  c
            jp   m,mr_w
            pop  af
            ret

; sd_fopen: HL = nombre (ASCII, 0-term). Devuelve A = handle (0FFh error).
sd_fopen:   call sd_clk
            ld   a,035h
            call mcu_send       ; cmd fopen
            push hl             ; longitud del nombre
            ld   b,0
so_len:     ld   a,(hl)
            or   a
            jr   z,so_lend
            inc  b
            inc  hl
            jr   so_len
so_lend:    pop  hl
            ld   a,b
            call mcu_send
so_loop:    ld   a,(hl)
            or   a
            jr   z,so_done
            call mcu_send
            inc  hl
            jr   so_loop
so_done:    call mcu_recv       ; handle
            ret

; sd_fclose: A = handle. Devuelve A = status.
sd_fclose:  ld   (sdh),a
            call sd_clk
            ld   a,039h
            call mcu_send
            ld   a,(sdh)
            call mcu_send
            call mcu_recv
            ret

; ---------------------------------------------------------------------
msgok:      defb 'Montado.',0Dh,0Ah,'$'
msgerr:     defb 'Error: no se pudo abrir el .img',0Dh,0Ah,'$'
msguse:     defb 'Uso: MOUNT3 d nombre.img  (d = A-D)',0Dh,0Ah,'$'

drive:      defb 0
sdh:        defb 0
dhptr:      defw 0
namebuf:    defs 16
