	title	'Root module of relocatable BIOS for CP/M 3.0'

	; version 1.0 15 Sept 82

true	equ -1
false	equ not true

banked	equ true
	

;		  Copyright (C), 1982
;		 Digital Research, Inc
;		     P.O. Box 579
;		Pacific Grove, CA  93950


;   This is the invariant portion of the modular BIOS and is
;	distributed as source for informational purposes only.
;	All desired modifications should be performed by
;	adding or changing externally defined modules.
;	This allows producing "standard" I/O modules that
;	can be combined to support a particular system 
;	configuration.

cr	equ 13
lf	equ 10
bell	equ 7
ctlQ	equ 'Q'-'@'
ctlS	equ 'S'-'@'

ccp	equ 0100h	; Console Command Processor gets loaded into the TPA

; 	cseg		; GENCPM puts CSEG stuff in common memory


    ; variables in system data page

;	extrn @covec,@civec,@aovec,@aivec,@lovec ; I/O redirection vectors
;	extrn @mxtpa				; addr of system entry point
;	extrn @bnkbf				; 128 byte scratch buffer

    ; initialization

;	extrn ?init			; general initialization and signon
;	extrn ?ldccp,?rlccp		; load & reload CCP for BOOT & WBOOT

    ; user defined character I/O routines

;	extrn ?ci,?co,?cist,?cost	; each take device in <B>
;	extrn ?cinit			; (re)initialize device in <C>
;	extrn @ctbl			; physical character device table

    ; disk communication data items

;	extrn @dtbl			; table of pointers to XDPHs
;	public @adrv,@rdrv,@trk,@sect	; parameters for disk I/O
;	public @dma,@dbnk,@cnt		;    ''       ''   ''  ''

    ; memory control

;	public @cbnk			; current bank
;	extrn ?xmove,?move		; select move bank, and block move
;	extrn ?bank			; select CPU bank

    ; clock support

;	extrn ?time			; signal time operation

    ; general utility routines

;	public ?pmsg,?pdec	; print message, print number from 0 to 65535
;	public ?pderr		; print BIOS disk error message header

	maclib modebaud		; define mode bits


    ; External names for BIOS entry points
    ;
    ; CPM3_SD81: la tabla de saltos ?boot/?wboot/?const/... NO vive aqui.
    ; Se movio a bank.z80 (duplicada al final del banco 3, igual que
    ; ?bank/map1blk) porque programas de usuario reales (WordStar, Turbo
    ; Pascal...) llaman a estas entradas DIRECTAMENTE, sin pasar por
    ; BDOS, para ganar velocidad -- y esas llamadas ocurren con el
    ; contexto "usuario" activo. Cada entrada en bank.z80 selecciona
    ; "sistema" (xor a / call ?bank) ANTES de saltar al cuerpo real
    ; (boot/wboot/const/... aqui abajo, sin modificar), asi que este
    ; fichero se queda con la logica de DRI intacta, solo se declaran
    ; publicas las etiquetas internas para que bank.z80 pueda llegar a
    ; ellas con extrn.

;	public boot,wboot,const,conin,conout,list,auxout,auxin
;	public home,seldsk,settrk,setsec,setdma,read,write
;	public listst,sectrn
;	public conost,auxist,auxost,devtbl,getdrv
;	public multio,flush,bnksel,setbnk


	; BOOT
	;	Initial entry point for system startup.

; 	dseg	; this part can be banked

boot:
	lxi sp,boot$stack
	mvi c,15	; initialize all 16 character devices
c$init$loop:
	push b
	call ?cinit
	pop b
	dcr c
	jp c$init$loop

	call ?init	; perform any additional system initialization
			; and print signon message

	lxi b,16*256+0
	lxi h,@dtbl	; init all 16 logical disk drives
d$init$loop:
	push b		; save remaining count and abs drive
	mov e,m
	inx h
	mov d,m
	inx h	; grab @drv entry
	mov a,e
	ora d
	jz d$init$next	; if null, no drive
	push h					; save @drv pointer 
	xchg					; XDPH address in <HL>
	dcx h
	dcx h
	mov a,m
	sta @RDRV	; get relative drive code
	mov a,c
	sta @ADRV	; get absolute drive code
	dcx h					; point to init pointer
	mov d,m
	dcx h
	mov e,m	; get init pointer
	xchg
	call ipchl	; call init routine
	pop h					; recover @drv pointer
d$init$next:
	pop b					; recover counter and drive #
	inr c
	dcr b
	jnz d$init$loop	; and loop for each drive
	jmp boot$1

; 	cseg	; following in resident memory
;
; CPM3_SD81: el "cseg" original de DRI significa "memoria comun de
; verdad" (banco 7, $E000-$FFFF, fijo en ambos contextos) -- NO
; duplicacion como hicimos con ?bank/map1blk/la tabla de saltos. Hace
; falta de verdad aqui: set$jumps cambia de banco A MITAD de su propia
; ejecucion (mvi a,1/call ?bnksl, para dejar "usuario" seleccionado
; antes de cargar la CCP en su TPA) y ?LUEGO SIGUE ejecutando mas
; codigo (escribir los vectores de pagina cero) -- si ese codigo (y la
; PILA que usa, boot$stack) viviera en el banco 3 normal, en cuanto el
; banco cambia bajo sus pies la CPU pasa a buscar instrucciones (y a
; hacer pop del "ret") en la pagina de usuario, que nunca tiene este
; codigo cargado -> ejecucion de basura (confirmado en hardware: PC se
; iba a $FFFF al hacer "ret" justo despues del cambio de banco). En
; banco 7 el problema no existe: ?bank solo reprograma los bancos 0-6,
; el 7 se queda igual pase lo que pase.
;
; $F598: hueco en el banco 7 (ver el mapa completo en memory_map.md)
; entre el final de RESBDOS.ASM y el bloque de ldccp_real ($F704).
; Antes estaba en $F200; se movio al empaquetar el
; banco 7 para hacerle sitio a RESBDOS.ASM entero.
; Requiere MC45 + sfast_mode_en activos para el fetch de instrucciones
; en esta zona (A14=1) -- ambos ya estan activos en este punto: MC45
; desde "start" (system.z80, antes de ?boot) y sfast_mode_en desde el
; POKE 2045,174 de ?init (init.z80), que se ejecuta ANTES de boot$1.

; CPM3_SD81: la posicion que llevabamos se guarda AQUI para poder
; retomarla al cerrar el bloque (ver "org bioskrnl$boot$save" mas abajo).
;
; OJO con el nombre: este fichero YA usa "bioskrnl$cseg$save" para el
; parentesis de $B800 (mas abajo, junto a ipchl). Son dos bloques
; distintos y necesitan cada uno su etiqueta.
; Antes ese cierre era un "org 06058h" literal -- la direccion calculada
; a mano de lo que venia detras de "jmp boot$1". Dejo de ser correcta en
; cuanto "start:" (system.z80) crecio 5 bytes al mover ahi mc45_ext67:
; el bucle de unidades de "boot:" se desplazo hasta $605C y se SOLAPO con
; seldsk, que seguia clavado en $6058. Dos "org" que se pisan no dan
; ningun error: el .lst mostraba "jnz d$init$loop" y el .cim tenia los
; bytes de seldsk encima. El sintoma fue un salto a $3279 y un HALT.
bioskrnl$boot$save equ $

	org 0F598h

boot$1:
	call set$jumps
	call ?ldccp				; fetch CCP for first time
	jmp ccp


	; WBOOT
	;	Entry for system restarts.

wboot:
	lxi sp,boot$stack
	call set$jumps		; initialize page zero
	call ?rlccp		; reload CCP
	jmp ccp			; then reset jmp vectors and exit to ccp


set$jumps:

  if banked
	mvi a,1
	call ?bnksl
  endif

	mvi a,JMP
	sta 0
	sta 5	; set up jumps in page zero
; CPM3_SD81: aqui iba "lxi h,?wboot". Ahora apunta a la tabla de saltos
; intermedia (BIOSTBL, loader.z80), porque $0001 no solo es el vector de
; arranque en caliente: es TAMBIEN de donde un programa de CP/M 2.2 saca
; la base del BIOS, restando 3 e indexando de tres en tres. Nuestra tabla
; real lleva el cambio de banco dentro de cada entrada y por tanto no
; tiene 3 bytes por entrada -- ver la nota larga en loader.z80.
;
; Como las dos cosas conviven en la misma palabra, la indireccion vale
; para ambas: "jmp 0" salta a BIOSTBL+3, que es "jp ?wboot".
	lxi h,BIOSTBL+3
	shld 1	; BIOS warm start entry (y base del BIOS para el usuario)
	lhld @MXTPA
	shld 6	; BDOS system call entry

; CPM3_SD81: inicializar TAMBIEN $0003 y $0004, que DRI no toca aqui.
; $0004 es "(usuario << 4) | unidad" y estaba quedandose con basura de
; la RAM del banco de usuario. Confirmado en hardware: valia $19, o sea
; nibble alto 1 (el "1" que la CCP imprimia en su prompt) y byte entero
; 25 (la unidad "Z" del mensaje de error). Las dos anomalias salian de
; este unico byte sin inicializar.
;
; Nota: esto se ejecuta tambien en el arranque en caliente, asi que de
; momento reinicia unidad/usuario en cada warm boot. No molesta porque
; la CCP reescribe $0004 desde ccp$curdrv/ccp$curusr del SCB en cada
; prompt; cuando esos campos se mantengan de verdad, revisar si conviene
; hacerlo solo en el arranque en frio.
	xra a
	sta 3	; IOBYTE
	sta 4	; unidad y usuario actuales
	ret


; CPM3_SD81: 56 en vez de los 64 de DRI -- el bloque comun del banco 7 va
; al byte y hacian falta 7 para inicializar $0003/$0004 (ver set$jumps).
; La cadena mas profunda que usa esta pila es boot$1 -> set$jumps ->
; ?bnksl, y ?bank tiene pila propia (bank$stack), asi que no pasa de 3-4
; niveles; 56 bytes son 28.
		ds 56
boot$stack	equ $



; =====================================================================
;  E/S de caracter -- FUERA del banco 7 (BKIOEXT, memmap.inc).
;
;  DRI la puso en "cseg" para que un programa pudiera llamar al BIOS sin
;  cambiar de banco. Esa premisa dejo de aplicar cuando metimos "biosw"
;  delante de cada entrada de la tabla (bank.z80): el envoltorio YA
;  selecciona sistema antes de saltar aqui y restaura el banco del
;  llamante al volver. Comprobados los dos caminos de entrada:
;
;    - ?const/?conin/?cono/?list/?auxo/?auxi/?conos/?auxis/?auxos/?lists
;      pasan por biosw.
;    - ?dvtbl/?drtbl hacen "xor a / call bnksel" antes del salto.
;
;  Y los alias de la BDOS (conoutf equ ?cono, etc.) apuntan a la tabla,
;  no al cuerpo. Nadie llega aqui con el banco de usuario puesto.
;
;  248 bytes de banco 7 recuperados, que es lo que hacia falta para
;  meter ahi los DPH y @dtbl.
; =====================================================================

bkio$save equ $              ; posicion en banco 7, se retoma al cerrar

	org BKIOEXT

	; DEVTBL
	;	Return address of character device table

devtbl:
	lxi h,@ctbl
	ret


	; GETDRV
	;	Return address of drive table

getdrv:
	lxi h,@dtbl
	ret



	; CONOUT
	;	Console Output.  Send character in <C>
	;			to all selected devices

conout:	

	lhld @covec	; fetch console output bit vector
	jmp out$scan


	; AUXOUT
	;	Auxiliary Output. Send character in <C>
	;			to all selected devices

auxout:
	lhld @aovec	; fetch aux output bit vector
	jmp out$scan


	; LIST
	;	List Output.  Send character in <C>
	;			to all selected devices.

list:
	lhld @lovec	; fetch list output bit vector

out$scan:
	mvi b,0		; start with device 0
co$next:
	dad h		; shift out next bit
	jnc not$out$device
	push h		; save the vector
	push b		; save the count and character
not$out$ready:
	call coster
	ora a
	jz not$out$ready
	pop b
	push b	; restore and resave the character and device
	call ?co	; if device selected, print it
	pop b		; recover count and character
	pop h		; recover the rest of the vector
not$out$device:
	inr b		; next device number
	mov a,h
	ora l	; see if any devices left
	jnz co$next	; and go find them...
	ret


	; CONOST
	;	Console Output Status.  Return true if
	;		all selected console output devices
	;		are ready.

conost:
	lhld @covec	; get console output bit vector
	jmp ost$scan


	; AUXOST
	;	Auxiliary Output Status.  Return true if
	;		all selected auxiliary output devices
	;		are ready.

auxost:
	lhld @aovec	; get aux output bit vector
	jmp ost$scan


	; LISTST
	;	List Output Status.  Return true if
	;		all selected list output devices
	;		are ready.

listst:
	lhld @lovec	; get list output bit vector

ost$scan:
	mvi b,0		; start with device 0
cos$next:
	dad h		; check next bit
	push h		; save the vector
	push b		; save the count
	mvi a,0FFh	; assume device ready
	cc coster	; check status for this device
	pop b		; recover count
	pop h		; recover bit vector
	ora a		; see if device ready
	rz		; if any not ready, return false
	inr b		; drop device number
	mov a,h
	ora l	; see if any more selected devices
	jnz cos$next
	ori 0FFh	; all selected were ready, return true
	ret

coster:		; check for output device ready, including optional
		;	xon/xoff support
	mov l,b
	mvi h,0	; make device code 16 bits
	push h			; save it in stack
	dad h
	dad h
	dad h	; create offset into device characteristics tbl
	lxi d,@ctbl+6
	dad d	; make address of mode byte
	mov a,m
	ani mb$xonxoff
	pop h			; recover console number in <HL>
	jz ?cost		; not a xon device, go get output status direct
	lxi d,xofflist
	dad d	; make pointer to proper xon/xoff flag
	call cist1		; see if this keyboard has character
	mov a,m
	cnz ci1	; get flag or read key if any
	cpi ctlq
	jnz not$q	; if its a ctl-Q,
	mvi a,0FFh 		;	set the flag ready
not$q:
	cpi ctls
	jnz not$s	; if its a ctl-S,
	mvi a,00h		;	clear the flag
not$s:
	mov m,a			; save the flag
	call cost1		; get the actual output status,
	ana m			; and mask with ctl-Q/ctl-S flag
	ret			; return this as the status

cist1:			; get input status with <BC> and <HL> saved
	push b
	push h
	call ?cist
	pop h
	pop b
	ora a
	ret

cost1:			; get output status, saving <BC> & <HL>
	push b
	push h
	call ?cost
	pop h
	pop b
	ora a
	ret

ci1:			; get input, saving <BC> & <HL>
	push b
	push h
	call ?ci
	pop h
	pop b
	ret


	; CONST
	;	Console Input Status.  Return true if
	;		any selected console input device
	;		has an available character.

const:
	lhld @civec	; get console input bit vector
	jmp ist$scan


	; AUXIST
	;	Auxiliary Input Status.  Return true if
	;		any selected auxiliary input device
	;		has an available character.

auxist:
	lhld @aivec	; get aux input bit vector

ist$scan:
	mvi b,0		; start with device 0
cis$next:
	dad h		; check next bit
	mvi a,0		; assume device not ready
	cc cist1	; check status for this device
	ora a
	rnz	; if any ready, return true
	inr b		; drop device number
	mov a,h
	ora l	; see if any more selected devices
	jnz cis$next
	xra a		; all selected were not ready, return false
	ret


	; CONIN
	;	Console Input.  Return character from first
	;		ready console input device.

conin:
	lhld @civec
	jmp in$scan


	; AUXIN
	;	Auxiliary Input.  Return character from first
	;		ready auxiliary input device.

auxin:
	lhld @aivec

in$scan:
	push h		; save bit vector
	mvi b,0
ci$next:
	dad h		; shift out next bit
	mvi a,0		; insure zero a  (nonexistant device not ready).
	cc cist1	; see if the device has a character
	ora a
	jnz ci$rdy	; this device has a character
	inr b		; else, next device
	mov a,h
	ora l	; see if any more devices
	jnz ci$next	; go look at them
	pop h		; recover bit vector
	jmp in$scan	; loop til we find a character

ci$rdy:
	pop h		; discard extra stack
	jmp ?ci

; xofflist estaba detras de bnksel en el fuente de DRI. Se trae aqui
; porque lo usa "coster", que acaba de mudarse -- asi el parentesis es
; uno solo en vez de dos.
xofflist	db	-1,-1,-1,-1,-1,-1,-1,-1		; ctl-s clears to zero
		db	-1,-1,-1,-1,-1,-1,-1,-1

; Guarda: detras viene rtc.z80 (RTCORG). Rellena hasta alli, que es
; memoria de sistema sin usar. Del tramo RTCORG..LDR_BASE se encarga la
; guarda de rtc.z80.
	ds RTCORG-$

	org bkio$save



;	Utility Subroutines

; CPM3_SD81: ipchl/?pmsg/?pdec/table10/?pderr NO necesitan memoria comun
; y se sacan del banco 7 (111 bytes recuperados para RESBDOS.ASM). Los
; unicos llamantes son "boot"/seldsk (mas arriba y mas abajo en este
; fichero, memoria banked), ?init (init.z80) y ?pderr entre si -- todos
; se ejecutan con "sistema" seleccionado y ninguno atraviesa un cambio
; de banco a mitad de rutina, que es el unico motivo real para estar en
; comun. Si alguna se llegara a llamar desde la tabla de saltos de
; bank.z80 tampoco pasaria nada: cada entrada de esa tabla selecciona
; "sistema" ANTES de saltar a la rutina real.
;
; $B800: memoria banked que RESBDOS.ASM deja libre al mudarse al banco 7
; (antes ocupaba $B700-$BC59). Justo detras del final de BDOS.ASM ($B7FF).

bioskrnl$cseg$save equ $

	org 0B800h

ipchl:		; vectored CALL point
	pchl


?pmsg:		; print message @<HL> up to a null
		; saves <BC> & <DE>
	push b
	push d
pmsg$loop:
	mov a,m
	ora a
	jz pmsg$exit
	mov c,a
	push h
	call ?cono
	pop h
	inx h
	jmp pmsg$loop
pmsg$exit:
	pop d
	pop b
	ret

?pdec:		; print binary number 0-65535 from <HL>
	lxi b,table10
	lxi d,-10000
next:
	mvi a,'0'-1
pdecl:
	push h
	inr a
	dad d
	jnc stoploop
	inx sp
	inx sp
	jmp pdecl
stoploop:
	push d
	push b
	mov c,a
	call ?cono
	pop b
	pop d
nextdigit:
	pop h
	ldax b
	mov e,a
	inx b
	ldax b
	mov d,a
	inx b
	mov a,e
	ora d
	jnz next
	ret

table10:
	dw	-1000,-100,-10,-1,0

?pderr:
	lxi h,drive$msg
	call ?pmsg	; error header
	lda @adrv
	adi 'A'
	mov c,a
	call ?cono	; drive code
	lxi h,track$msg
	call ?pmsg	; track header
	lhld @trk
	call ?pdec	; track number
	lxi h,sector$msg
	call ?pmsg	; sector header
	lhld @sect
	call ?pdec	; sector number
	ret

; CPM3_SD81: fin del parentesis en memoria banked -- volvemos al bloque
; comun del banco 7 exactamente donde lo dejamos (ver arriba).

	org bioskrnl$cseg$save


	; BNKSEL
	;	Bank Select.  Select CPU bank for further execution.

bnksel:
	sta @cbnk 			; remember current bank
	jmp ?bank			; and go exit through users
					; physical bank select routine



; CPM3_SD81: guarda de tamano. Antes rellenaba hasta $F704 (ldccp_real,
; init.z80); ahora para en DTBLORG, porque el hueco que dejo la E/S de
; caracter al mudarse a BKIOEXT lo ocupan @dtbl y los XDPH/DPH -- que
; TIENEN que ser comunes porque BIOS SELDSK y DRVTBL devuelven sus
; direcciones a los programas. Ver memmap.inc y drvtbl.z80.
; Del tramo DTBLORG..$F704 se encarga la guarda de drvtbl.z80.

	ds DTBLORG-$



; 	dseg	; following resides in banked memory
;
; CPM3_SD81: de vuelta a memoria banked normal (sistema, banco 3) --
; solo el bloque de arriba (boot$1..bnksel+xofflist, mas boot$stack)
; necesitaba banco 7. Se retoma la posicion exacta que llevabamos justo
; detras de "jmp boot$1", asi que todo lo de aqui abajo (seldsk..flush,
; @adrv..@dbnk) y los ficheros que vienen despues (bank.z80, etc.) siguen
; donde les toca, crezca lo que crezca lo de delante.
;
; Esto era un "org 06058h" literal y se solapo con "boot:" en cuanto
; "start:" crecio 5 bytes -- ver la nota junto al "org 0F598h" de arriba.

	org bioskrnl$boot$save



;	Disk I/O interface routines


	; SELDSK
	;	Select Disk Drive.  Drive code in <C>.
	;		Invoke login procedure for drive
	;		if this is first select.  Return
	;		address of disk parameter header
	;		in <HL>

seldsk:
	mov a,c
	sta @adrv	; save drive select code
	mov l,c
	mvi h,0
	dad h	; create index from drive code
	lxi b,@dtbl
	dad b	; get pointer to dispatch table
	mov a,m
	inx h
	mov h,m
	mov l,a	; point at disk descriptor
	ora h
	rz	; if no entry in table, no disk
	mov a,e
	ani 1
	jnz not$first$select	; examine login bit
	push h
	xchg	; put pointer in stack & <DE>
	lxi h,-2
	dad d
	mov a,m
	sta @RDRV	; get relative drive
	lxi h,-6
	dad d	; find LOGIN addr
	mov a,m
	inx h
	mov h,m
	mov l,a	; get address of LOGIN routine
	call ipchl				; call LOGIN
	pop h					; recover DPH pointer
not$first$select:
	ret


	; HOME
	;	Home selected drive.  Treated as SETTRK(0).

home:
	lxi b,0		; same as set track zero


	; SETTRK
	;	Set Track. Saves track address from <BC> 
	;		in @TRK for further operations.

settrk:
	mov l,c
	mov h,b
	shld @trk
	ret


	; SETSEC
	;	Set Sector.  Saves sector number from <BC>
	;		in @sect for further operations.

setsec:
	mov l,c
	mov h,b
	shld @sect
	ret


	; SETDMA
	;	Set Disk Memory Address.  Saves DMA address
	;		from <BC> in @DMA and sets @DBNK to @CBNK
	;		so that further disk operations take place
	;		in current bank.

setdma:
	mov l,c
	mov h,b
	shld @dma

; CPM3_SD81: era "lda @cbnk". La semantica original (ver el comentario de
; DRI justo arriba) es "el banco de DMA por defecto es el banco del que
; LLAMA", y con el BIOS de DRI eso era @cbnk porque a setdma se llegaba
; sin tocar el paginado. Aqui no: ?stdma pasa por biosd, que hace
; "xor a / call bnksel" -- y bnksel es "sta @cbnk / jmp ?bank", asi que
; cuando se ejecuta esta linea @cbnk YA vale 0. Resultado: @dbnk = 0
; siempre, o sea "el DMA esta en el banco de sistema".
;
; No se nota con la BDOS (que efectivamente llama desde el banco 0, y
; ademas corrige con setbnkf justo despues de cada seek), pero SI con los
; programas que llaman al BIOS por la tabla de $0001: el sector se les
; copia al banco de sistema en vez de a su buffer. Caso real: el RSX
; DIRLBL de SET.COM, que lee el directorio con SELDSK/SETTRK/SETSEC/
; SETDMA/READ y nunca llama a SETBNK -- veia su buffer vacio, no
; encontraba ninguna SFCB ($21) y soltaba "Directory needs to be
; re-formatted... Please see INITDIR" sobre un disco perfectamente
; formateado (y de paso volcaba el sector encima del propio XIOS).
;
; BD_BNK es el banco del llamante, que biosd guarda antes de conmutar;
; vive en banco 7, asi que se lee igual bajo cualquier paginado. Para la
; BDOS vale 0 igual que antes (no cambia nada); para un programa vale 1,
; que es justo lo que hace DRI en el post-proceso de la funcion 50
; ("cpi 12 / lxi d,dir$bios3" -> "mvi a,1 / jmp setbnkf", BDOS.ASM:7541).
	lda BD_BNK	; default DMA bank is current bank
			; fall through to set DMA bank

	; SETBNK
	;	Set Disk Memory Bank.  Saves bank number
	;		in @DBNK for future disk data
	;		transfers.

setbnk:
	sta @dbnk
	ret


	; SECTRN
	;	Sector Translate.  Indexes skew table in <DE>
	;		with sector in <BC>.  Returns physical sector
	;		in <HL>.  If no skew table (<DE>=0) then
	;		returns physical=logical.

sectrn:
	mov l,c
	mov h,b
	mov a,d
	ora e
	rz
	xchg
	dad b
	mov l,m
	mvi h,0
	ret


	; READ
	;	Read physical record from currently selected drive.
	;		Finds address of proper read routine from
	;		extended disk parameter header (XDPH).

read:
	lhld @adrv
	mvi h,0
	dad h	; get drive code and double it
	lxi d,@dtbl
	dad d	; make address of table entry
	mov a,m
	inx h
	mov h,m
	mov l,a	; fetch table entry
	push h				; save address of table
	lxi d,-8
	dad d	; point to read routine address
	jmp rw$common			; use common code


	; WRITE
	;	Write physical sector from currently selected drive.
	;		Finds address of proper write routine from
	;		extended disk parameter header (XDPH).

write:
	lhld @adrv
	mvi h,0
	dad h	; get drive code and double it
	lxi d,@dtbl
	dad d	; make address of table entry
	mov a,m
	inx h
	mov h,m
	mov l,a	; fetch table entry
	push h				; save address of table
	lxi d,-10
	dad d	; point to write routine address

rw$common:
	mov a,m
	inx h
	mov h,m
	mov l,a	; get address of routine
	pop d				; recover address of table
	dcx d
	dcx d	; point to relative drive
	ldax d
	sta @rdrv	; get relative drive code and post it
	inx d
	inx d	; point to DPH again
	pchl				; leap to driver


	; MULTIO
	;	Set multiple sector count. Saves passed count in
	;		@CNT

multio:
	sta @cnt
	ret


	; FLUSH
	;	BIOS deblocking buffer flush.  Not implemented.

flush:
	xra a
	ret	; return with no error



	; error message components
drive$msg	db	cr,lf,bell,'BIOS Error on ',0
track$msg	db	': T-',0
sector$msg	db	', S-',0


    ; disk communication data items

@adrv	ds	1		; currently selected disk drive
@rdrv	ds	1		; controller relative disk drive
@trk	ds	2		; current track number
@sect	ds	2		; current sector number
@dma	ds	2		; current DMA address
@cnt	db	0		; record count for multisector transfer
@dbnk	db	0		; bank for DMA operations


; 	cseg	; common memory
;
; CPM3_SD81: @cbnk tiene el mismo problema que boot$1 (ver arriba) pero
; con una variable en vez de con codigo: bnksel hace "sta @cbnk" ANTES
; de que ?bank cambie de banco -- es decir, escribe en la copia del
; banco 3 que esta activa EN ESE MOMENTO (la que se esta abandonando).
; Si @cbnk viviera en banco 3 normal, la copia de la pagina de destino
; nunca se actualiza, y una lectura posterior de @cbnk desde el otro
; contexto leeria basura/desactualizado -- mismo tipo de aliasing por
; pagina, aqui en un dato en vez de en codigo. En banco 7 (comun, banco
; 3 no lo toca) esto no puede pasar.
;
; $E064: cuando se eligio, se creia que era "justo detras de las
; variables del SCB". Eso era con la base del SCB mal puesta en $E000;
; con la base correcta ($E09C, ver SCB.ASM) $E064 cae en realidad en la
; zona BAJA de la pagina, la de variables internas de la BDOS. Sigue
; siendo seguro -- comprobado que BDOS.ASM no define ningun campo por
; debajo de $E090 (el mas bajo es olog, scb$pg+090h) -- pero la razon es
; otra: esta libre, no "detras del SCB".

	org 0E064h

@cbnk	db	0		; bank for processor operations

; CPM3_SD81: @cbnk era el ultimo byte antes de este "org 0E064h" (ver
; arriba) -- sin este "org" de vuelta, todo lo que se ensambla despues
; de este fichero (SCB.ASM no ocupa bytes, son puros "equ"; bank.z80,
; move.z80, diskio.z80, drvtbl.z80, chario.z80, init.z80) empezaria a
; colocarse en banco 7 a partir de $E065, chocando con ATTR_val/
; DFILE_val/FONT_ADDR. $62E9 es donde continuaba la secuencia antes de
; mover boot$1/@cbnk (ahi es donde caia dup_switcher, bank.z80).

	org 062E9h

	end
