	title	'CP/M 3 Banked BDOS Resident Module, Dec 1982'
;***************************************************************
;***************************************************************
;**                                                           **
;**   B a s i c    D i s k   O p e r a t i n g   S y s t e m  **
;**                                                           **
;**   R e s i d e n t   M o d u l e  -  B a n k e d  B D O S  **
;**                                                           **
;***************************************************************
;***************************************************************

;/*
;  Copyright (C) 1978,1979,1980,1981,1982
;  Digital Research
;  P.O. Box 579
;  Pacific Grove, CA 93950
;
;  December, 1982
;
;*/
;
ssize		equ	30
diskfx		equ	12
conoutfxx	equ	2
printfx		equ	9
constatfx	equ	11
setdmafx	equ	26
chainfx		equ	47
ioloc		equ	3

; CPM3_SD81: 'org 0000h'/'base equ $' y todo el bloque de equates de
; pagina relativa (bnkbdos$pg/resbdos$pg/scb$pg/bios$pg y los 29
; "xxxf") quitados -- este fichero se concatena dentro del mismo
; ensamblado que BDOS.ASM, que YA define bootf..xmovef (alias a
; nuestras rutinas reales de bank.z80, ver mas abajo en BDOS.ASM) y
; todas las variables del SCB (fx, dcnt, hash, etc.) que este fichero
; usa directamente sin declararlas (ni siquiera con extrn -- la fuente
; original tampoco las declara: se apoya en que RMAC resuelve
; simbolos no definidos como externos automaticamente al enlazar; aqui
; equivale simplemente a compartir el mismo ambito de ensamblado).
;
; bnkbdos/error$jmp SI son propios de este fichero (no los define
; BDOS.ASM) -- alias directos a la entrada real de la BDOS (bdose) y a
; su trampolin de error en el SCB (error, definido en BDOS.ASM como
; scb$pg+$FB -- ver la nota ahi sobre quien debe rellenarlo con el
; "jmp error$sub" real).
bnkbdos		equ	bdose
error$jmp 	equ	error

sconoutf	equ	conoutf		; 31. escape sequence decoded conout
screenf		equ	0ffffh		; 32. screen function

; =====================================================================
; CPM3_SD81: MODULO ENTERO EN MEMORIA COMUN (banco 7, $F040)
;
; Este fichero es, literalmente, lo que DRI titula "Resident Module"
; (ver la cabecera de arriba): esta pensado por diseno para vivir en
; memoria comun, y hasta ahora lo teniamos en memoria banked de sistema
; ($B700-$BC59), que es la causa raiz del ultimo bug que quedaba.
;
; El motivo NO es exclusivo de este hardware -- es la misma condicion
; que en cualquier CP/M+ bancado: hay codigo aqui que cambia de contexto
; a mitad de su propia ejecucion y SIGUE ejecutando despues, asi que sus
; propias instrucciones tienen que seguir estando donde estaban cuando
; el contexto cambia. Casos confirmados leyendo el fuente:
;
;   - disk$function: "call bank$bdos" y todo el copiado de FCB/DMA de
;     vuelta que viene DESPUES (bank$bdos acaba en "mvi a,1 / jmp
;     selmemf", o sea vuelve al llamante con "usuario" ya activo).
;   - parse: mismo patron (call bank$bdos y sigue).
;   - rb$goback: restaura rb$entsp (el SP real de la CCP, que solo
;     significa algo bajo "usuario") y hace ret.
;   - qconinx / switch1: seleccionan "usuario" un instante para leer un
;     byte del programa de usuario y vuelven -- con su propio codigo
;     ejecutandose durante el cambio.
;   - rb$func10 y rb$blk$out1: llaman a bank$bdos y continuan.
;
; Y los datos que se escriben bajo un contexto y se leen bajo el otro
; (rb$aret, rb$entsp, commonfcb, common$dma -- estos dos ultimos con el
; nombre que ya lo dice) tambien tienen que estar aqui por lo mismo.
;
; $F032: ver el mapa completo del banco 7 en memory_map.md. El sitio
; salio de empaquetar SCB/ATTR/DFILE (estaban alineados a 2 KB sin
; necesitarlo) y de sacar de comun las rutinas de impresion de
; BIOSKRNL.ASM, que no lo necesitaban.
; =====================================================================

	org 0F032h

rb$serial:	db	'654321'

	jmp	bdos
	jmp	move$out	;A = bank #
				;HL = dest, DE = srce
	jmp	move$tpa	;A = bank #
				;HL = dest, DE = srce
	jmp 	rb$search$hash	;A = bank #
				;HL = hash table address

	; on return, Z flag set for eligible DCNTs
	;	     Z flag reset implies unsuccessful rb$search

	; Additional variables referenced directly by bnkbdos

hashmx:		dw	0	;max hash rb$search dcnt
rd$dir$flag:	db	0	;read directory flag -- CPM3_SD81: renombrado
				; desde 'rd$dir' (choca con el alias de la RUTINA homonima
				; 'rd$dir'=rddir en BDOS30.ASM, ver BDOS.ASM) para que
				; coincida con el nombre que ya usa BDOS.ASM para este flag
make$xfcb:	db	0	;Make XFCB flag
find$xfcb:	db	0	;Search XFCB flag
xdcnt:		dw	0	;current xdcnt

xdmaadd:	dw	common$dma
curdma:		dw	0
copy$cr$only:	db	0
user$info:	dw	0
kbchar:		db	0
		jmp	qconinx

bdos:	;arrive here from user programs
	mov a,c ; c = BDOS function #
	
	;switch to local stack

	lxi h,0
	shld rb$aret
	dad sp
	shld rb$entsp ; save stack pointer
	lxi sp,lstack
	lxi h,rb$goback
	push h

	cpi diskfx
	jnc disk$func

	sta fx			;[JCE] DRI patch 1

	lxi h,rb$functab
	mvi b,0
	dad b
	dad b
	mov a,m
	inx h
	mov h,m
	mov l,a
	pchl

	maclib	makedate	;[JCE] Dates all go in one file
	@LCOPY
	@BDATE
	dw	0,0,0,0,0,0,0,0,0,0,0

rb$functab:
	dw	wbootf, bank$bdos, bank$bdos, rb$func3
	dw	func4, func5, rb$func6, rb$func7
	dw	rb$func8, rb$func9, rb$func10, bank$bdos

rb$func3:
	call readerf
	jmp rb$sta$ret

func4:
	mov c,e
	jmp punchf

func5:
	mov c,e
	jmp listf

rb$func6:
	mov a,e
	inr a
	jz rb$dirinp	;0ffh -> cond. input
	inr a
	jz rb$dirstat		;0feh -> status
	inr a
	jz rb$dirinp1		;0fdh -> input
	mov c,e
	jmp conoutf		;	 output
rb$dirstat:
	call rb$constx
	jmp rb$sta$ret
rb$dirinp:
	call rb$constx
	ora a
	rz
rb$dirinp1:
	call rb$conin
	jmp rb$sta$ret

rb$constx:
	lda kbchar
	ora a
	mvi a,0ffh
	rnz
	jmp constf

rb$conin:
	lxi h,kbchar
	mov a,m
	mvi m,0
	ora a
	rnz
	jmp coninf

rb$func7:
	call auxinstf
	jmp rb$sta$ret

rb$func8:
	call auxoutstf
	jmp rb$sta$ret

rb$func9:
	mov b,d
	mov c,e
rb$print:
	lxi h,outdelim
	ldax b
	cmp m
	rz
	inx b
	push b
	mov c,a
	call blk$out0
	pop b
	jmp rb$print

rb$func10:
	xchg
	mov a,l
	ora h
	jnz func10a
	lxi h,buffer+2
	shld conbuffadd
	lhld dmaad
func10a:
	push h
	lxi d,buffer
	push d
	mvi b,0
	mov c,m
	inx b
	inx b
	inx b
	xchg
	call movef
	mvi m,0
	pop d
	push d
	mvi c,10
	call bank$bdos
	lda buffer+1
	mov c,a
	mvi b,0
	inx b
	inx b
	pop d
	pop h
	jmp movef

rb$func111:
rb$func112:
	sta res$fx
	xchg
	mov e,m
	inx h
	mov d,m
	inx h
	mov c,m
	inx h
	mov b,m
	xchg
	; hl = addr of string
	; bc = length of string
rb$blk$out:
	mov a,b
	ora c
	rz
	push b
	push h
	mov c,m
	lxi d,rb$blk$out2
	push d
	lda res$fx
	cpi 112
	jz listf

blk$out0:
	lda conmode
	mov b,a
	ani 2
	jz rb$blk$out1
	mov a,b
	ani 14h
	jz rb$blk$out1
	ani 10h
	jnz sconoutf
	jmp conoutf

rb$blk$out1:
	mov e,c
	mvi c,conoutfxx
	jmp bank$bdos

rb$blk$out2:
	pop h
	inx h
	pop b
	dcx b
	jmp rb$blk$out

qconinx:
	; switch to bank 1
	mvi a,1
	call selmemf
	; get character
	mov b,m
	; return to bank zero
	xra a
	call selmemf
	; return with character in A
	mov a,b
	ret

switch1:
	lxi d,switch0
	push d
	mvi a,1
	call selmemf
	pchl
switch0:
	mov b,a
	xra a
	call selmemf
	mov a,b
	ret

; CPM3_SD81: aqui habia un stub "badfunc" que devolvia $FF. Se puso
; porque zmac daba ese simbolo por indefinido, y resulto ser un
; ESPEJISMO: en los ensambladores de DRI (MAC/RMAC) el "$" dentro de un
; identificador SE IGNORA -- es solo un separador de legibilidad. O sea
; que "badfunc" (como lo escriben los saltos de disk$func, lineas 236-237
; del fuente original) y "bad$func" (como esta escrita la etiqueta, linea
; 339) son EL MISMO SIMBOLO para DRI. zmac los trata como distintos.
;
; El stub tapaba por tanto el manejador real, y con el la funcion 152
; (parse filename): la CCP recibia un FCB sin tocar y NINGUNA orden se
; reconocia. Los saltos apuntan ahora a bad$func.

disk$func:
	cpi ndf
	jc OKdf ;func < ndf
	cpi 98
	jc bad$func ;ndf < func < 98
	cpi nxdf
	jnc bad$func ;func >= nxdf
	cpi 111
	jz rb$func111
	cpi 112
	jz rb$func112
	jmp disk$function

    OKdf:
	cpi 17
	jz rb$search
	cpi 18
	jz rb$searchn
	cpi setdmafx
	jnz disk$function

	; Set dma addr
	xchg
	shld dmaad
	shld curdma
	ret

    rb$search:
	xchg
	shld searcha
	
    rb$searchn:
	lhld searcha
	xchg

disk$function:

;
;	Perform the required buffer tranfers from
;	the user bank to common memory
;

	lxi h,dfctbl-12
	mov a,c
	cpi 98
	jc normalCPM
	lxi h,xdfctbl-98
    normalCPM:
	mvi b,0
	dad b
	mov a,m

; ****  SAVE DFTBL ITEM, INFO, & FUNCTION *****
 
	mov b,a
	push b
	push d

	rar
	jc cpycdmain			;cdmain test
	rar
	jc cpyfcbin			;fcbin test
	jmp nocpyin

    cpycdmain:
	lhld dmaad
	xchg
	lxi h,common$dma
	lxi b,16
	call movef
	pop d
	push d

    cpyfcbin:
	xra a
	sta copy$cr$only
	lxi h,commonfcb
	lxi b,36
	call movef
	lxi d,commonfcb
	pop h
	pop b
	push b
	push h
	shld user$info

    nocpyin:

	call bank$bdos

	pop d ;restore FCB address
	pop b
	mov a,b ;restore fcbtbl byte & function #
	ani 0fch
	rz	;[JCE] DRI Patch 13: F8 -> FC
	lxi h,commonfcb
	xchg
	lxi b,33
	ral
	jc copy$fcb$back			;fcbout test
	mvi c,36
	ral
	jc copy$fcb$back		;pfcbout test
	ral
	jc cdmacpyout128			;cdmaout128 test
	mvi c,4
	ral
	jc movef			;timeout test
	ral
	jc cdmacpyout003			;cdmaout003 test
	mvi c,6
	jmp movef			;seriout 

    copy$fcb$back:
	lda copy$cr$only
	ora a
	jz movef
	lxi b,14
	dad b
	xchg
	dad b
	mov a,m
	stax d
	inx h
	inx d
	mov a,m
	stax d
	inx b
	inx b
	inx b
	dad b
	xchg
	dad b
	ldax d
	mov m,a
	ret

    cdmacpyout003:
	lhld dmaad
	lxi b,3
	lxi d,common$dma
	jmp movef

    cdmacpyout128:
	lhld dmaad
	lxi b,128
	lxi d,common$dma
	jmp movef

parse:
	xchg
	mov e,m
	inx h
	mov d,m
	inx h
	mov c,m
	inx h
	mov b,m
	lxi h,buffer+133
	push h
	push b
	push d
	shld buffer+2
	lxi h,buffer+4
	shld buffer
	lxi b,128
	call movef
	mvi m,0
	mvi c,152
	lxi d,buffer
	call bank$bdos
	pop b
	mov a,l
	ora h
	jz parse1
	mov a,l
	ana h
	inr a
	jz parse1
	lxi d,buffer+4
	mov a,l
	sub e
	mov l,a
	mov a,h
	sbb d
	mov h,a
	dad b
	shld rb$aret
parse1:
	pop h
	pop d
	lxi b,36
	jmp movef

bad$func:
	cpi 152
	jz parse

	; A = 0 if fx >= 128, 0ffh otherwise
	ral
	mvi a,0
	jc rb$sta$ret

	dcr a

rb$sta$ret:
	sta rb$aret

rb$goback:
; CPM3_SD81: garantizar "usuario" antes de tocar nada del programa de
; usuario. Este es el UNICO punto de salida de la BDOS residente, y a
; partir de la linea siguiente todo lo que se toca es memoria suya: el
; SP que se restaura (rb$entsp) y la direccion de retorno que saca el
; "ret" final. Con "sistema" activo, esa misma direccion numerica cae en
; la pagina fisica equivocada -- en el bloque 0 eso es la ROM del ZX81,
; y el "ret" se lleva la ejecucion ahi (confirmado en hardware: sacaba
; $7E09, que son bytes de la ROM en $0C18).
;
; No basta con que bank$bdos deje "usuario" al salir, porque hay caminos
; que llegan aqui SIN pasar por el: las funciones de dispositivo
; (rb$func3/6/7/8 -> readerf/constf/coninf/auxinstf...) llaman a la
; tabla de saltos de bank.z80, cuyas entradas seleccionan sistema y no
; lo restauran, y de ahi caen en rb$sta$ret -> aqui.
;
; Arreglarlo en cada entrada de la tabla seria lo ideal, pero son muchas
; y el bloque duplicado ($7E00-$7FFF) va justo; ponerlo aqui lo hace
; incondicional y en el sitio con el significado exacto. Es la misma
; garantia que bank$bdos ya se da a si misma al salir ("mvi a,1 / jmp
; selmemf"). Ojo con el orden: selmemf destruye A y HL, asi que los
; valores de retorno (A, B y HL, de rb$aret) se cargan DESPUES.
	mvi a,1
	call selmemf

	lhld rb$entsp
	sphl ;user stack restored
	lhld rb$aret
	mov a,l
	mov b,h ;BA = HL = rb$aret
	ret

BANK$BDOS:

	xra a
	call selmemf

	call bnkbdos

	shld rb$aret
	mvi a,1
	jmp selmemf ;ret


move$out:
	ora a
	jz movef	; era 'move$f': mismo typo de transcripcion que en otros sitios
	call selmemf
move$ret:
	call movef
	xra a
	jmp selmemf

move$tpa:
	mvi a,1
	call selmemf
	jmp move$ret

rb$search$hash: ; A = bank # , HL = hash table addr

	; Hash format
	; xxsuuuuu xxxxxxxx xxxxxxxx ssssssss
	; x = hash code of fcb name field
	; u = low 5 bits of fcb user field
	;     1st bit is on for XFCB's
	; s = shiftr(mod || ext,extshf)

	shld rb$hash$tbla
	call selmemf
	; Push return address
	lxi h,rb$search$h7
	push h
	; Reset read directory record flag
	xra a
	sta rd$dir$flag

	lhld rb$hash$tbla
	mov b,h
	mov c,l
	lhld hashmx
	xchg
	; Return with Z flag set if dcnt = hash$mx
	lhld dcnt
	push h
	call rb$subdh
	pop d
	ora l
	rz
	; Push hash$mx-dcnt (# of hash$tbl entries to rb$search)
	; Push dcnt+1
	push h
	inx d
	xchg
	push h
	; Compute .hash$tbl(dcnt-1)
	dcx h
	dad h
	dad h
	dad b
rb$search$h1:
	; Advance hl to address of next hash$tbl entry
	lxi d,4
	dad d
	lxi d,hash
	; Do hash u fields match?
	ldax d
	xra m
	ani 1fh
	jnz rb$search$h3 ; no
	; Do hash's match?
	call rb$search$h6
	jz rb$search$h4 ; yes
rb$search$h2:
	xchg
	pop h
rb$search$h25:
	; de = .hash$tbl(dcnt), hl = dcnt
	; dcnt = dcnt + 1
	inx h
	xthl
	; hl = # of hash$tbl entries to rb$search
	; decrement & test for zero
	; Restore stack & hl to .hash$tbl(dcnt)
	dcx h
	mov a,l
	ora h
	xthl
	push h
	; Are we done?
	xchg
	jnz rb$search$h1 ; no - keep searching
	; Search unsuccessful - return with Z flag reset
	inr a
	pop h
	pop h
	ret
rb$search$h3:
	; Does xdcnt+1 = 0ffh?
	lda xdcnt+1
	inr a
	jz rb$search$h5 ; yes
	; Does xdcnt+1 = 0feh?
	inr a
	jnz rb$search$h2 ; no - continue searching
	; Do hash's match?
	push d
	call rb$search$h6
	pop d
	jnz rb$search$h2 ; no
	; Does find$xfcb = 0ffh?
	lda find$xfcb
	inr a
	jz rb$search$h45 ; yes
	; Does find$xfcb = 0feh?
	inr a
	jz rb$search$h35 ; yes
	; xdcnt+1 = 0feh & find$xfcb < 0feh
	; Open user 0 rb$search
	; Does hash u field = 0?
	mov a,m
	ani 1fh
	jnz rb$search$h2 ; no
	; Search successful
	jmp rb$search$h4
rb$search$h35:
	; xdcnt+1 = 0feh & find$xfcb = 0feh
	; Delete rb$search to return matching fcb's & xfcbs
	; Do hash user fields match?
	ldax d
	xra m
	ani 0fh
	jnz rb$search$h2 ; no
	; Exclude empty fcbs, sfcbs, and dir lbls
	mov a,m
	ani 30h
	cpi 30h
	jz rb$search$h2
rb$search$h4:
	; successful rb$search
	; Set dcnt to rb$search$hash dcnt-1
	; dcnt gets incremented by read$dir
	; Also discard rb$search$hash loop count
	lhld dcnt
	xchg
	pop h
	dcx h
	shld dcnt
	pop b
	; Does dcnt&3 = 3?
	mov a,l
	ani 03h
	cpi 03h
	rz ; yes
	; Does old dcnt & new dcnt reside in same sector?
	mov a,e
	ani 0fch
	mov e,a
	mov a,l
	ani 0fch
	mov l,a
	call rb$subdh
	ora l
	rz ; yes
	; Set directory read flag
	mvi a,0ffh
	sta rd$dir$flag
	xra a
	ret
rb$search$h45:
	; xdcnt+1 = 0feh, find$xfcb = 0ffh
	; Rename rb$search to save dcnt of xfcb in xdcnt
	; Is hash entry an xfcb?
	mov a,m
	ani 10h
	jz rb$search$h2 ; no
	; Do hash user fields agree?
	ldax d
	xra m
	ani 0fh
	jnz rb$search$h2 ; no
	; set xdcnt
	jmp rb$search$h55
rb$search$h5:
	; xdcnt+1 = 0ffh
	; Make rb$search to save dcnt of empty fcb
	; is hash$tbl entry empty?
	mov a,m
	cpi 0f5h
	jnz rb$search$h2 ; no
rb$search$h55:
	; xdcnt = dcnt
	xchg
	pop h
	shld xdcnt
	jmp rb$search$h25
rb$search$h6:
	; hash rb$compare routine
	; Is hashl = 0?
	lda hashl
	ora a
	rz ; yes - hash rb$compare successful
	; hash$mask = 0e0h if hashl = 3
	;           = 0c0h if hashl = 2
	mov c,a
	rrc
	rrc
	rar
	mov b,a
	; hash s field does not pertain if hashl ~= 3
	; Does hash(0) fields match?
	ldax d
	xra m
	ana b
	rnz ; no
	; Compare remainder of hash fields for hashl bytes
	push h
	inx h
	inx d
	call rb$compare
	pop h
	ret
rb$search$h7:
	; Return to bnkbdos
	push a
	xra a
	call selmemf
	pop a
	ret

rb$subdh: 
	;compute HL = DE - HL
	mov a,e
	sub l
	mov l,a
	mov a,d
	sbb h
	mov h,a
	ret

rb$compare:
	ldax d
	cmp m
	rnz
	inx h
	inx d
	dcr c
	rz
	jmp rb$compare

;	Disk Function Copy Table

cdmain	equ	00000001B	;copy 1ST 16 bytes of DMA to
				;common$dma on entry
fcbin	equ	00000010b	;fcb copy on entry
fcbout	equ	10000000b	;fcb copy on exit
pfcbout	equ	01000000b	;random fcb copy on exit
cdma128	equ	00100000b	;copy 1st 128 bytes of common$dma 
				;to DMA on exit
timeout equ	00010000b	;copy date & time on exit
cdma003 equ	00001000B	;copy 1ST 3 bytes of common$dma
				;to DMA on exit
serout  equ	00000100b	;copy rb$serial # on exit

; CPM3_SD81: dfctbl/xdfctbl (54 bytes) van en memoria comun, como el
; resto del modulo, aunque sean tablas de solo lectura.
;
; Hubo un intento de dejarlas en memoria banked ($B780) para ahorrar
; espacio comun, razonando que disk$function solo las consulta en su
; prologo ("lxi h,dfctbl-12 / dad b / mov a,m") y que ese prologo corria
; bajo "sistema". ERROR, confirmado en hardware: la BDOS residente se
; entra con el banco de USUARIO puesto (ver call5_entry, init.z80), asi
; que ese prologo lee con usuario activo -- y $B780 bajo usuario es
; memoria de la CCP, no esta tabla. El despacho entero iba a ciegas.
;
; Se quedan aqui, en el hueco del final del banco 7. "nxdf" vale lo
; mismo este donde este: es una resta de dos direcciones del mismo
; bloque.

resbdos$cseg$save equ $

	org 0F7B8h

dfctbl:
	db 0			; 12=return version #
	db 0			; 13=reset disk system
	db 0			; 14=select disk
	db fcbin+fcbout+cdmain  ; 15=open file
	db fcbin+fcbout		; 16=close file
	db fcbin+cdma128        ; 17=rb$search first
	db fcbin+cdma128      	; 18=rb$search next
	db fcbin+cdmain		; 19=delete file
	db fcbin+fcbout		; 20=read sequential
	db fcbin+fcbout		; 21=write sequential
	db fcbin+fcbout+cdmain	; 22=make file
	db fcbin+cdmain		; 23=rename file
	db 0			; 24=return login vector
	db 0			; 25=return current disk
	db 0			; 26=set DMA address
	db 0			; 27=get alloc address
	db 0			; 28=write protect disk
	db 0			; 29=get R/O vector
	db fcbin+fcbout+cdmain	; 30=set file attributes
	db 0			; 31=get disk param addr
	db 0			; 32=get/set user code
	db fcbin+fcbout		; 33=read random
	db fcbin+fcbout		; 34=write random
	db fcbin+pfcbout	; 35=compute file size
	db fcbin+pfcbout	; 36=set random record
	db 0			; 37=drive reset
	db 0			; 38=access drive
 	db 0			; 39=free drive
	db fcbin+fcbout		; 40=write random w/ zero fill

	db fcbin+fcbout		; 41=test & write record
	db 0			; 42=record lock
	db 0			; 43=record unlock
	db 0			; 44=set multi-sector count
	db 0			; 45=set BDOS error mode
	db cdma003		; 46=get disk free space
	db 0     		; 47=chain to program
	db 0			; 48=flush buffers
	db fcbin		; 49=Get/Set system control block
	db fcbin		; 50=direct BIOS call (CP/M)
ndf equ ($-dfctbl)+12

xdfctbl:
	db 0			; 98=reset allocation vectors
	db fcbin+cdmain		; 99=truncate file
	db fcbin+cdmain		; 100=set directory label
	db 0     		; 101=return directory label data
	db fcbin+fcbout+cdmain	; 102=read file xfcb
	db fcbin+cdmain		; 103=write or update file xfcb
	db fcbin		; 104=set current date and time
	db fcbin+timeout	; 105=get current date and time
	db fcbin		; 106=set default password
	db fcbin+serout	 	; 107=return rb$serial number
	db 0			; 108=get/set program return code
	db 0			; 109=get/set console mode
	db 0			; 110=get/set output delimiter
	db 0			; 111=rb$print block
	db 0			; 112=list block

nxdf equ ($-xdfctbl)+98

; CPM3_SD81: guarda de tamano del hueco del final del banco 7 (las tablas
; de arriba). Detras solo queda $F800, donde empieza @bnkbf.
	ds 0F800h-$

; CPM3_SD81: fin del parentesis -- de vuelta al bloque principal del
; modulo, exactamente donde lo dejamos. Todo lo que viene debajo (rb$aret,
; commonfcb, common$dma, rb$entsp, los vectores de intercepcion del BIOS)
; SI necesita ser comun: se escribe bajo un contexto y se lee bajo el otro.

	org resbdos$cseg$save

res$fx:	ds	1
rb$hash$tbla:
	ds	2
bank:	ds	1
rb$aret:	ds	2	;address value to return

buffer:			;function 10 256 byte buffer

commonfcb:
	ds	36	;fcb copy in common memory

common$dma:
        ds	220	;function 10 buffer cont.

; CPM3_SD81: "ds ssize*2 / lstack:" (la pila propia de la BDOS, que
; "bdos:" activa con "lxi sp,lstack" nada mas entrar) se movio al banco
; 7 (init.z80, junto a ldccp_real/call5_entry) -- viviendo aqui, en
; memoria de sistema normal, cualquier cambio de contexto que ocurra
; MIENTRAS SP apunta aqui (p.ej. qconinx, que activa "usuario" un
; instante para leer un byte del programa de usuario) corrompe lo que
; se lea despues de un push, aunque el propio banco 3 (donde vive el
; codigo) no cambie -- confirmado en hardware con un trazado paso a
; paso (RET final de la BDOS sacando una direccion de vuelta que era
; basura). Common (@bnkbf tiene el mismo motivo para estar ahi).
;
; PERO el "ds ssize*2" que habia DELANTE de lstack si tiene que seguir
; aqui, y no es relleno: separa el buffer de 256 bytes (commonfcb +
; common$dma) de rb$entsp. rb$func10 copia "maxlen+3" bytes al buffer,
; asi que un programa que pida una linea de mas de 252 caracteres
; escribiria justo encima de rb$entsp -- o sea, encima del SP al que la
; BDOS tiene que volver. Al mover lstack al banco 7 nos llevamos por
; error tambien estos 60 bytes; repuestos.
		ds	60
rb$entsp:	ds	2

; BIOS intercept vector

wbootfx:	jmp	wbootf
		jmp	switch1
constfx:	jmp	constf
		jmp	switch1
coninfx:	jmp	coninf
		jmp	switch1
conoutfx:	jmp	conoutf
		jmp	switch1
listfx:		jmp	listf
		jmp	switch1
		
		dw	0,0,0
		dw	0
		dw	0

; CPM3_SD81: bloque "olog/rlog/patch$flgs/SCB:...bdosadd:" (registro
; de log, nivel de parches, y la estructura completa del SCB -- hashl
; hasta bdosadd) quitado entero. Redundante con las equ de BDOS.ASM
; (scb$pg=$E000 mas olog/rlog/SCB/hashl/.../bdosadd -- ver ahi), que
; ya apuntan a esta misma RAM real del banco 7 sin necesitar reserva
; de almacenamiento explicita (igual que @CIVEC etc en SCB.ASM: son
; solo direcciones, banco 7 siempre esta mapeado). Mantener ambas
; copias habria sido "Mult. def." (probado). El "end" que traia esta
; fuente tambien se quita -- bdos_full.z80 pone el suyo al final del
; ensamblado conjunto.

; CPM3_SD81: guarda de tamano. El banco 7 va justo y los bloques se
; colocan con "org" absolutos, asi que si este modulo creciera mas de la
; cuenta se comeria en silencio el bloque comun de BIOSKRNL.ASM ($F598)
; sin que el ensamblador dijera nada. Con esto, pasarse da un "ds"
; negativo y el ensamblado falla. Rellena el hueco con ceros, que no
; cuesta nada: el .cim es plano y esas direcciones ya estaban dentro.

	ds 0F598h-$


