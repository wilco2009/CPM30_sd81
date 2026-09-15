	title 'System Control Block Definition for CP/M3 BIOS'

;	public @civec, @covec, @aivec, @aovec, @lovec, @bnkbf
;	public @crdma, @crdsk, @vinfo, @resel, @fx, @usrcd 
;        public @mltio, @ermde, @erdsk, @media, @bflgs
;	public @date, @hour, @min, @sec, ?erjmp, @mxtpa


; CPM3_SD81: reubicado de $FE00 (default DRI) a $E000 -- $FE00 cae
; dentro de nuestra tabla de fuentes ($F800-$FFFF, I=$F8), y el SCB
; tambien define @BNKBF (mas abajo) que por tanto ya no se declara
; aparte en move.z80. La PAGINA del SCB ocupa exactamente 256 bytes
; ($E000-$E0FF: el campo mas alto es bdosadd = scb$pg+0FEh, ver
; BDOS.ASM), y ATTR_val empieza justo detras, en $E100 -- ver el mapa
; completo del banco 7 en memory_map.md.
;
; CPM3_SD81: OJO -- "base del SCB" NO es lo mismo que "base de la pagina
; del SCB". Los offsets de este fichero (@CIVEC=+22h, @MXTPA=+62h...)
; son del SCB PUBLICO, que empieza $9C bytes dentro de la pagina; lo de
; debajo son variables internas de la BDOS. Estaba puesto a $E000 (la
; pagina) en vez de a $E09C (el SCB), o sea TODOS los simbolos "@"
; apuntaban $9C bytes por debajo de su sitio.
;
; Las tres fuentes coinciden en el $9C:
;   CCP3.ASM:162   pag$off equ 09ch   (todos sus campos son pag$off+n)
;   BDOS.ASM:119   SCB     equ scb$pg+09ch
;   Comprobacion:  conwidth es scb$pg+0B6h para la BDOS y pag$off+1Ah
;                  para la CCP -- $9C+$1A = $B6.
;
; Y con la base correcta encajan dos campos que lo confirman:
;   @MXTPA = base+62h = $E0FE = "bdosadd" de la BDOS (mismo campo).
;   ?ERJMP = base+5Fh = $E0FB = "error"   de la BDOS (el vector de error
;            que rellena GENSYS; ver ?init, init.z80).
;
; Sintoma que producia: la BDOS y el BIOS usaban direcciones distintas
; para los mismos campos (p.ej. @COVEC del BIOS en $E024 contra
; conout$rflg de la BDOS en $E0C0), y la CCP leia conwidth/conpage/
; bdosbase a cero, con lo que su arranque iba a ciegas.
; CPM3_SD81 (fase 2): era 0E09CH a pelo, y tenia que cuadrar a mano con
; el scb$pg de BDOS.ASM. Los dos salen ya de SCB_PAGE (memmap.inc).
scb$base equ    SCB_PAGE+9Ch    ; Base del SCB publico (pagina + 9Ch)

@CIVEC  equ     scb$base+22h    ; Console Input Redirection 
                                ; Vector (word, r/w)
@COVEC  equ     scb$base+24h    ; Console Output Redirection 
                                ; Vector (word, r/w)
@AIVEC  equ     scb$base+26h    ; Auxiliary Input Redirection 
                                ; Vector (word, r/w)
@AOVEC  equ     scb$base+28h    ; Auxiliary Output Redirection 
                                ; Vector (word, r/w)
@LOVEC  equ     scb$base+2Ah    ; List Output Redirection 
                                ; Vector (word, r/w)
; CPM3_SD81: OJO -- en el SCB de DRI, scb$base+35h NO es el buffer: es
; un PUNTERO de 2 bytes ("Address of 128 Byte Buffer", r/o) donde el
; BIOS deja la direccion de su buffer de 128 bytes. Nuestro codigo
; (move.z80, diskio.z80, init.z80) usa @bnkbf como si fuera el buffer
; en si ("ld hl,@bnkbf" + ldir de 128 bytes), asi que con el valor
; original ($E035) cada copia entre bancos arrasaba 128 bytes del SCB
; a partir de $E035 -- o sea @cbnk ($E064), olog ($E090), rlog ($E092),
; hashl/hash ($E09C/$E09D), version ($E0A1), util$flgs, dspl$flgs,
; clp$flgs, ccp$comlen, ccp$curdrv, ccp$curusr, ccp$conbuff y ccp$flgs
; ($E0B3). Y lo usa hasta ldccp_real, o sea en la propia carga de la CCP.
;
; @cbnk es el peor de todos: es donde bnksel apunta cual es el contexto
; activo, y ?bank/dup_switcher lo consultan. Cada ldir de 128 bytes por
; @bnkbf lo dejaba con un byte cualquiera del sector copiado.
;
; Apuntado ahora a 128 bytes de verdad, propios, al final del banco 7
; ($F800-$F87F, ocupando los glifos de los codigos 0-15 de la tabla
; de fuentes, que no son imprimibles nunca). Sigue siendo
; memoria comun, que es lo que exige su funcion (?move escribe aqui
; bajo un contexto y lee bajo el otro).
;
; PENDIENTE: si alguna parte de la BDOS llega a leer scb$base+35h
; esperando el puntero, habra que ademas guardar ahi esta direccion
; ("ld hl,@BNKBF / ld (scb$base+35h),hl" en ?init). No se ha visto
; ningun sitio que lo haga, pero no se ha revisado exhaustivamente.
@BNKBF  equ     0F800h          ; buffer de 128 bytes del BIOS bancado
@CRDMA  equ     scb$base+3Ch    ; Current DMA Address 
                                ; (word, r/o)
@CRDSK  equ     scb$base+3Eh    ; Current Disk (byte, r/o)
@VINFO  equ     scb$base+3Fh    ; BDOS Variable "INFO" 
                                ; (word, r/o)
@RESEL  equ     scb$base+41h    ; FCB Flag (byte, r/o)
@FX     equ     scb$base+43h    ; BDOS Function for Error 
                                ; Messages (byte, r/o)
@USRCD  equ     scb$base+44h    ; Current User Code (byte, r/o)
@MLTIO	equ	scb$base+4Ah	; Current Multi-Sector Count
				; (byte,r/w)
@ERMDE  equ     scb$base+4Bh    ; BDOS Error Mode (byte, r/o)
@ERDSK	equ	scb$base+51h	; BDOS Error Disk (byte,r/o)
@MEDIA	equ	scb$base+54h	; Set by BIOS to indicate
				; open door (byte,r/w)
@BFLGS  equ     scb$base+57h    ; BDOS Message Size Flag (byte,r/o)  
@DATE   equ     scb$base+58h    ; Date in Days Since 1 Jan 78 
                                ; (word, r/w)
@HOUR   equ     scb$base+5Ah    ; Hour in BCD (byte, r/w)
@MIN    equ     scb$base+5Bh    ; Minute in BCD (byte, r/w)
@SEC    equ     scb$base+5Ch    ; Second in BCD (byte, r/w)
?ERJMP  equ     scb$base+5Fh    ; BDOS Error Message Jump
                                ; (word, r/w)
@MXTPA  equ     scb$base+62h    ; Top of User TPA 
                                ; (address at 6,7)(word, r/o)
	end

