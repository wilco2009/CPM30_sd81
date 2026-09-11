	title	'CP/M BDOS Interface, BDOS, Version 3.0 Dec, 1982'
;*****************************************************************
;*****************************************************************
;**                                                             **
;**   B a s i c    D i s k   O p e r a t i n g   S y s t e m    **
;**								**
;**            I n t e r f a c e   M o d u l e                  **
;**                                                             **
;*****************************************************************
;*****************************************************************
;
;	Copyright (c) 1978, 1979, 1980, 1981, 1982
;	Digital Research
;	Box 579, Pacific Grove
;	California
;
;       December 1982
;
on	equ	0ffffh
off	equ	00000h
; CPM3_SD81: MPM/BANKED quitados -- ya cumplieron su unico proposito
; (decidir las ramas if/else en el preprocesado, ver memory_map.md) y
; no se usan como valores en ningun sitio del codigo (solo en mis
; propios comentarios de traza) -- colisionaban con "banked" de
; BIOSKRNL.ASM (zmac no distingue mayus/minus) sin aportar nada.

;
;	equates for non graphic characters
;

ctla	equ	01h	; control a
ctlb	equ	02h	; control b
ctlc	equ	03h	; control c
ctle	equ	05h	; physical eol
ctlf	equ	06h	; control f
ctlg	equ	07h	; control g
ctlh	equ	08h	; backspace
ctlk	equ	0bh	; control k
ctlp	equ	10h	; prnt toggle
ctlq	equ	11h	; start screen
ctlr	equ	12h	; repeat line
ctls	equ	13h	; stop screen
ctlu	equ	15h	; line delete
ctlw	equ	17h	; control w
ctlx	equ	18h	; =ctl-u
ctlz	equ	1ah	; end of file
rubout	equ	7fh	; char delete
tab	equ	09h	; tab char
cr	equ	0dh	; carriage return
lf	equ	0ah	; line feed
ctl	equ	5eh	; up arrow

; CPM3_SD81: $8900 (no $0000) -- tiene que quedar CONTIGUO con el resto
; del XIOS ($6000 en adelante) para que "LOAD FAST SYSTEM.BIN CODE
; 24576" (un solo bloque plano desde $6000) cargue tambien esto. $0000
; rompia la carga (desplazaba TODO el fichero $6000 bytes de mas,
; arranque muerto). $8800 (primer intento) tambien fallo: colisionaba
; con "in_mcu_send" de init.z80 (ambos resolvian a $8807) porque
; calcule el final del XIOS con una direccion vieja, de antes de
; reescribir ldccp_real (crecio con el bucle de copia de la CCP) --
; confirmado en hardware con un trazado paso a paso: en vez de
; ejecutar in_mcu_send, saltaba a "bdose"/"bdose2" (BDOS.ASM). El
; final real del XIOS es "noccp_msg" en $8848 (+6 = $884E) -- $8900 dej
; margen de sobra. Cabe en los bloques 4-5 (hasta ~$BD00), sin
; necesitar mc45_ext67.
		org	08900h
base		equ	$

; CPM3_SD81: bnkbdos$pg/resbdos$pg/bios$pg (offsets relativos a "base")
; quitados -- ver la nota de mas abajo, "System Control Block equates",
; y bank.z80/RESBDOS.ASM. scb$pg SI se mantiene, pero apuntando a
; nuestra direccion real (banco 7, $E000 -- la misma base que usa nuestro
; SCB.ASM para @CIVEC etc: los rangos de offset no se solapan, $22-$62
; ahi, $90-$FE aqui abajo -- las dos mitades de la misma estructura).
scb$pg		equ	0E000h

; Bios equates -- alias directos a bank.z80 (tabla de saltos real,
; duplicada en banco 3 para ser alcanzable desde cualquier contexto).
; Sustituye tanto al bios$pg+N generico como al caso especial "if
; BANKED" (wbootf..listf via scb$pg -- ese mecanismo dependia de que
; GENSYS grabase trampolines de verdad en el SCB, que no tenemos; nuestra
; tabla de saltos ya resuelve el mismo problema de otra forma).
bootf		equ	?boot		; 00. cold boot function
wbootf		equ	?wboot		; 01. warm boot function
constf		equ	?const		; 02. console status function
coninf		equ	?conin		; 03. console input function
conoutf		equ	?cono		; 04. console output function
listf		equ	?list		; 05. list output function
punchf		equ	?auxo		; 06. punch output function
readerf		equ	?auxi		; 07. reader input function
homef		equ	?home		; 08. disk home function
seldskf		equ	?sldsk		; 09. select disk function
settrkf		equ	?sttrk		; 10. set track function
setsecf		equ	?stsec		; 11. set sector function
setdmaf		equ	?stdma		; 12. set dma function
readf		equ	?read		; 13. read disk function
writef		equ	?write		; 14. write disk function
liststf		equ	?lists		; 15. list status function
sectran		equ	?sctrn		; 16. sector translate
conoutstf	equ	?conos		; 17. console output status function
auxinstf	equ	?auxis		; 18. aux input status function
auxoutstf	equ	?auxos		; 19. aux output status function
devtblf		equ	?dvtbl		; 20. return device table address fx
devinitf	equ	?devin		; 21. initialize device function
drvtblf		equ	?drtbl		; 22. return drive table address
multiof		equ	?mltio		; 23. multiple i/o function
flushf		equ	?flush		; 24. flush function
movef		equ	?mov		; 25. memory move function
timef		equ	?tim		; 26. system get/set time function
selmemf		equ	?bnksl		; 27. select memory function
setbnkf		equ	?stbnk		; 28. set dma bank function
xmovef		equ	?xmov		; 29. extended move function

; System Control Block equates

olog		equ	scb$pg+090h
rlog		equ	scb$pg+092h

SCB		equ	scb$pg+09ch

; Expansion Area - 6 bytes

hashl		equ	scb$pg+09ch
hash		equ	scb$pg+09dh
version		equ	scb$pg+0a1h

; Utilities Section - 8 bytes

util$flgs	equ	scb$pg+0a2h
dspl$flgs	equ	scb$pg+0a6h

; CLP Section - 4 bytes

clp$flgs	equ	scb$pg+0aah
clp$errcde	equ	scb$pg+0ach

; CCP Section - 8 bytes

ccp$comlen	equ	scb$pg+0aeh
ccp$curdrv	equ	scb$pg+0afh
ccp$curusr	equ	scb$pg+0b0h
ccp$conbuff	equ	scb$pg+0b1h
ccp$flgs	equ	scb$pg+0b3h

; Device I/O Section - 32 bytes

conwidth	equ	scb$pg+0b6h
column		equ	scb$pg+0b7h
conpage		equ	scb$pg+0b8h
conline		equ	scb$pg+0b9h
conbuffadd	equ	scb$pg+0bah
conbufflen	equ	scb$pg+0bch
conin$rflg	equ	scb$pg+0beh
conout$rflg	equ	scb$pg+0c0h
auxin$rflg	equ	scb$pg+0c2h
auxout$rflg	equ	scb$pg+0c4h
lstout$rflg	equ	scb$pg+0c6h
page$mode	equ	scb$pg+0c8h
pm$default	equ	scb$pg+0c9h
ctlh$act	equ	scb$pg+0cah
rubout$act	equ	scb$pg+0cbh
type$ahead	equ	scb$pg+0cch
contran		equ	scb$pg+0cdh
conmode		equ	scb$pg+0cfh
outdelim	equ	scb$pg+0d3h
listcp		equ	scb$pg+0d4h
qflag		equ	scb$pg+0d5h

; BDOS Section - 42 bytes

scbadd		equ	scb$pg+0d6h
dmaad		equ	scb$pg+0d8h
olddsk		equ	scb$pg+0dah
info		equ	scb$pg+0dbh
resel		equ	scb$pg+0ddh
relog 		equ	scb$pg+0deh
fx		equ	scb$pg+0dfh
usrcode		equ	scb$pg+0e0h
dcnt		equ	scb$pg+0e1h
;searcha	equ	scb$pg+0e3h
searchl		equ	scb$pg+0e5h
multcnt		equ	scb$pg+0e6h
errormode	equ	scb$pg+0e7h
searchchain	equ	scb$pg+0e8h
temp$drive	equ	scb$pg+0ech
errdrv      	equ	scb$pg+0edh
media$flag	equ	scb$pg+0f0h
bdos$flags	equ	scb$pg+0f3h
stamp		equ	scb$pg+0f4h
commonbase	equ	scb$pg+0f9h
error		equ	scb$pg+0fbh	;jmp error$sub
bdosadd		equ	scb$pg+0feh

; CPM3_SD81: bloque "Resbdos equates" (resbdos$pg+N: move$out, move$tpa,
; srch$hash, hashmx, rd$dir$flag, make$xfcb, find$xfcb, xdcnt, xdmaad,
; curdma, copy$cr$only, user$info, kbchar, qconinx) quitado entero --
; RESBDOS.ASM (concatenado en el mismo ensamblado, ver bdos_full.z80)
; define esos mismos nombres directamente como etiquetas reales, sin
; falta indireccion via resbdos$pg. Nota: RESBDOS.ASM originalmente
; llamaba "rd$dir" a este flag, pero ese nombre ya lo usa BDOS30.ASM
; como alias de la RUTINA "rddir" (homonimos por casualidad en la
; fuente DRI) -- renombrado ahi a "rd$dir$flag" para evitar el choque.

;
serial: db	'654321'
;
;	Enter here from the user's program with function number in c,
;	and information address in d,e
;

bdose:	; Arrive here from user programs
	xchg
	shld info
	xchg ; info=de, de=info

	mov a,c
	sta fx
	cpi 14
	jc bdose2
	lxi h,0
	shld dircnt ; dircnt,multnum = 0
	lda olddsk
	sta bd$seldsk ; Set bd$seldsk

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	dcr a
	sta copy$cr$init
; CPM3_SD81: [endif] (linea 240)

	; If mult$cnt ~= 1 then bd$read or bd$write commands
	; are handled by the shell
	lda mult$cnt
	dcr a
	jz bdose2
	lxi h,mult$fxs
bdose1:
	mov a,m
	ora a
	jz bdose2
	cmp c
	jz shell
	inx h
	jmp bdose1
bdose2:
	mov a,e
	sta linfo ; linfo = low(info) - don't equ
	lxi h,0
	shld aret ; Return value defaults to 0000
	shld resel ; resel,relog = 0
	; Save user's stack pointer, set to local stack
	dad sp
	shld entsp ; entsp = stackptr

; CPM3_SD81: [if not BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 268)

	lxi h,goback ; Return here after all functions
	push h ; jmp goback equivalent to ret
	mov a,c
	cpi nfuncs
	jnc high$fxs ; Skip if invalid #
	mov c,e ; possible output character to c
	lxi h,functab
	jmp bdos$jmp
	; look for functions 98 ->
high$fxs:
	cpi 128
	jnc test$152
	sui 98
	jc lret$eq$ff ; Skip if function < 98
	cpi nfuncs2
	jnc lret$eq$ff
	lxi h,functab2
bdos$jmp:
	mov e,a
	mvi d,0 ; de=func, hl=.ciotab
	dad d
	dad d
	mov e,m
	inx h
	mov d,m ; de=functab(func)
	lhld info ; info in de for later xchg	
	xchg
	pchl ; dispatched

;	   CAUTION: In banked systems only,
;          error$sub is referenced indirectly by the SCB ERROR
; 	   field in RESBDOS as (0fc7ch).  This value is converted
; 	   to the actual address of error$sub by GENSYS.  If the offset
; 	   of error$sub is changed, the SCB ERROR value must also
; 	   be changed.

;
;	error subroutine
;

error$sub:
	mvi b,0
	push b
	dcr c
	lxi h,errtbl
	dad b
	dad b
	mov e,m
	inx h
	mov d,m
	xchg
	call errflg
	pop b
	lda error$mode
	ora a
	rnz
	jmp reboote

mult$fxs:	db	20,21,33,34,40,0

	maclib	makedate

; CPM3_SD81: bloque de alias movido al final del fichero (ver el final
; de BDOS.ASM) -- casi todos son referencias HACIA DELANTE (apuntan a
; etiquetas definidas miles de bytes mas abajo), y un "equ" hacia
; delante tan pronto en el fichero desestabilizaba la resolucion de
; direcciones en varias pasadas (confirmado: causaba "Phase error" en
; sitios sin relacion aparente, como "bdose2" unas pocas lineas mas
; arriba, y "Mult. def." fantasma en RESBDOS.ASM). Los alias en si no
; cambian de significado por estar mas abajo -- el codigo que los usa
; se resuelve igual sea cual sea el orden del "equ" en el fichero.
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	@LCOPY
	@BDATE
	ds	5
; CPM3_SD81: [else] (linea 335)
; CPM3_SD81: [endif] (linea 347)

;	dispatch table for functions

functab:
	dw	rebootx1, func1, func2, func3
	dw	punchf, listf, func6, func7
	dw	func8, func9, func10, func11
diskf	equ	($-functab)/2	; disk funcs
	dw	func12,func13,func14,func15
	dw	func16,func17,func18,func19
	dw	func20,func21,func22,func23
	dw	func24,func25,func26,func27
	dw	func28,func29,func30,func31
	dw	func32,func33,func34,func35
	dw	func36,func37,func38,func39
	dw	func40,lret$eq$ff,func42,func43
	dw	func44,func45,func46,func47
	dw	func48,func49,func50
nfuncs	equ	($-functab)/2

functab2:
	dw	func98,func99
	dw	func100,func101,func102,func103
	dw	func104,func105,func106,func107
	dw	func108,func109,func110,func111
	dw	func112

nfuncs2	equ	($-functab2)/2

errtbl:
	dw	permsg
	dw	rodmsg
	dw	rofmsg
	dw	selmsg
	dw	0
	dw	0
	dw	passmsg
	dw	fxstsmsg
	dw	wildmsg

test$152:
	cpi 152
	rnz

;
;	PARSE version 3.0b  Oct 08 1982 - Doug Huskey
;
;
      	; DE->.(.filename,.fcb)
	;
	; filename = [d:]file[.type][;password]
	;             
	; fcb assignments
	;
	;   0     => drive, 0 = default, 1 = A, 2 = B, ...
	;   1-8   => file, converted to upper case,
	;            padded with blanks (left justified)
	;   9-11  => type, converted to upper case,
	;	     padded with blanks (left justified)
	;   12-15 => set to zero
	;   16-23 => password, converted to upper case,
	;	     padded with blanks
	;   24-25 => 0000h
	;   26    => length of password (0 - 8)
	;
	; Upon return, HL is set to FFFFH if DE locates
	;            an invalid file name;
	; otherwise, HL is set to 0000H if the delimiter
	;            following the file name is a 00H (NULL)
	; 	     or a 0DH (CR);
	; otherwise, HL is set to the address of the delimiter
	;            following the file name.
	;
	lxi 	h,sthl$ret
	push	h
	lhld 	info
	mov	e,m		;get first parameter
	inx	h
	mov	d,m
	push	d		;save .filename
	inx	h
	mov	e,m		;get second parameter
	inx	h
	mov	d,m
	pop	h		;DE=.fcb  HL=.filename
	xchg
parse0:
	push	h		;save .fcb
	xra	a
	mov	m,a		;clear drive byte
	inx	h
	lxi	b,20h*256+11
	call	pad		;pad name and type w/ blanks
	lxi	b,4
	call	pad		;EXT, S1, S2, RC = 0
	lxi	b,20h*256+8
	call	pad		;pad password field w/ blanks
	lxi	b,12
	call	pad		;zero 2nd 1/2 of map, cr, r0 - r2
;
;	skip spaces
;
	call	skps
;
;	check for drive
;
	ldax	d
	cpi	':'		;is this a drive?
	dcx	d
	pop	h
	push	h		;HL = .fcb
	jnz	parse$name
;
;	Parse the drive-spec
;
parsedrv:
	call 	delim
	jz	parse$ok
	sui	'A'
	jc	perror1
	cpi	16
	jnc	perror1
	inx	d
	inx	d		;past the ':'
	inr	a		;set drive relative to 1
	mov	m,a		;store the drive in FCB(0)
;
;	Parse the file-name
;
parse$name:
	inx	h		;HL = .fcb(1)
	call	delim
	jz	parse$ok
	lxi	b,7*256

parse6:	ldax	d		;get a character
	cpi	'.'		;file-type next?
	jz	parse$type	;branch to file-type processing
	cpi	';'
	jz	parse$pw
	call	gfc		;process one character
	jnz	parse6		;loop if not end of name
	jmp	parse$ok
;
;	Parse the file-type
;
parse$type:	
	inx	d		;advance past dot
	pop	h
	push	h		;HL =.fcb
	lxi	b,9
	dad	b		;HL =.fcb(9)
	lxi	b,2*256

parse8:	ldax	d
	cpi	';'
	jz	parsepw
	call	gfc		;process one character
	jnz	parse8		;loop if not end of type
;
parse$ok:
	pop	b
	push	d
	call	skps		;skip trailing blanks and tabs
	dcx	d
	call	delim		;is next nonblank char a delim?
	pop	h
	rnz			;no
	lxi	h,0
	ora	a
	rz			;return zero if delim = 0
	cpi	cr
	rz			;return zero if delim = cr
	xchg
	ret
;
;	handle parser error
;
perror:
	pop	b			;throw away return addr
perror1:
	pop	b
	lxi	h,0ffffh
	ret
;
;	Parse the password
;
parsepw:
	inx	d
	pop	h
	push	h
	lxi	b,16
	dad	b
	lxi	b,7*256+1
parsepw1:
	call	gfc
	jnz	parsepw1
	mvi	a,7
	sub	b
	pop	h
	push	h
	lxi	b,26
	dad	b
	mov	m,a
	ldax	d			;delimiter in A
	jmp	parse$ok
;
;	get next character of name, type or password
;
gfc:	call	delim		;check for end of filename
	rz			;return if so
	cpi	' '		;check for control characters
	inx	d
	jc	perror		;error if control characters encountered
	inr	b		;error if too big for field
	dcr	b
	jm	perror
	inr	c
	dcr	c
	jnz	gfc1
	cpi	'*'		;trap "match rest of field" character
	jz	setmatch
gfc1:	mov	m,a		;put character in fcb
	inx	h
	dcr	b		;decrement field size counter
	ora	a		;clear zero flag
	ret
;;
setmatch:
	mvi	m,'?'		;set match one character
	inx	h
	dcr	b
	jp	setmatch
	ret
;	
;	check for delimiter
;
;	entry:	A = character
;	exit:	z = set if char is a delimiter
;
delimiters:	db	cr,tab,' .,:;[]=<>|',0

delim:	ldax	d		;get character
	push	h
	lxi	h,delimiters
delim1:	cmp	m		;is char in table
	jz	delim2
	inr	m
	dcr	m		;end of table? (0)
	inx	h
	jnz	delim1
	ora	a		;reset zero flag
delim2:	pop	h
	rz
	;
	;	not a delimiter, convert to upper case
	;
	cpi	'a'
	rc
	cpi	'z'+1
	jnc	delim3
	ani 	05fh
delim3:	ani	07fh	
	ret			;return with zero set if so
;
;	pad with blanks or zeros
;
pad:	mov	m,b
	inx	h
	dcr	c
	jnz	pad
	ret
;
;	skip blanks and tabs
;
skps:	ldax	d
	inx	d
	cpi	' '		;skip spaces & tabs
	jz 	skps
	cpi	tab
	jz	skps
	ret
;
;	end of PARSE
;

errflg:
	; report error to console, message address in hl
	push h
	call crlf ; stack mssg address, new line
	lda adrive
	adi 'A'
	sta dskerr ; current disk name
	lxi b,dskmsg

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	call zprint ; the error message
; CPM3_SD81: [else] (linea 645)
; CPM3_SD81: [endif] (linea 647)

	pop b

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	lda bdos$flags
	ral
	jnc zprint
	call zprint ; error message tail
	lda fx
	mvi b,30h
	lxi h,pr$fx1
	cpi 100
	jc errflg1
	mvi m,31h
	inx h
	sui 100
errflg1:
	sui 10
	jc errflg2
	inr b
	jmp errflg1
errflg2:
	mov m,b
	inx h
	adi 3ah
	mov m,a
	inx h
	mvi m,20h
	lxi h,pr$fcb
	mvi m,0
	lda resel
	ora a
	jz errflg3
	mvi m,20h
	push d
	lhld info
	inx h
	xchg
	lxi h,pr$fcb1
	mvi c,8
	call move
	mvi m,'.'
	inx h
	mvi c,3
	call move
	pop d
errflg3:
	call crlf
	lxi b,pr$fx
	jmp zprint

zprint:
	ldax b
	ora a
	rz
	push b
	mov c,a
	call tabout
	pop b
	inx b
	jmp zprint

pr$fx:	db	'BDOS Function = '
pr$fx1:	db	'   '
pr$fcb:	db	' File = '
pr$fcb1:ds	12
	db	0

; CPM3_SD81: [else] (linea 716)
; CPM3_SD81: [endif] (linea 718)

reboote: 
	lxi h,0fffdh
	jmp rebootx0 ; BDOS error
rebootx:
;;;	lxi h,0fffeh ; CTL-C error
	call patch$1e25	;[JCE] DRI Patch 13
rebootx0:
	shld clp$errcde
rebootx1:
	jmp wbootf

entsp:	ds	2	; entry stack pointer

shell:
	lxi h,0
	dad sp
	shld shell$sp

; CPM3_SD81: [if not BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 740)

	lxi h,shell$rtn
	push h
	call save$rr
	call save$dma
	lda mult$cnt
mult$io:
	push a
	sta mult$num
	call cbdos
	ora a
	jnz shell$err
	lda fx
	cpi 33
	cnc incr$rr
	call adv$dma
	pop a
	dcr a
	jnz mult$io
	mov h,a
	mov l,a
	ret

shell$sp:	dw	0

		dw	0c7c7h,0c7c7h,0c7c7h,0c7c7h,0c7c7h

shell$stk:		; shell has 5 level stack
hold$dma:	dw	0

cbdos:
	lda fx
	mov c,a
cbdos1:
	lhld info
	xchg
	jmp bdose2

adv$dma:
	lhld dmaad
	lxi d,80h
	dad d
	jmp reset$dma1

save$dma:
	lhld dmaad
	shld hold$dma
	ret

reset$dma:
	lhld hold$dma
reset$dma1:
	shld dmaad
	jmp bd$setdma

shell$err:
	pop b
	inr a
	rz
	lda mult$cnt
	sub b
	mov h,a
	ret

shell$rtn:
	push h
	lda fx
	cpi 33
	cnc reset$rr
	call reset$dma
	pop d
	lhld shell$sp
	sphl
	xchg
	mov a,l
	mov b,h
	ret

	page


	title	'CP/M Bdos Interface, Bdos, Version 3.0 Nov, 1982'
;*****************************************************************
;*****************************************************************
;**                                                             **
;**   B a s i c    D i s k   O p e r a t i n g   S y s t e m    **
;**								**
;**               C o n s o l e   P o r t i o n                 **
;**                                                             **
;*****************************************************************
;*****************************************************************
;
;       November 1982
;
;
;	Console handlers
;
bd$conin:
	;bd$read console character to A
	lxi h,kbchar
	mov a,m
	mvi m,0
	ora a
	rnz
	;no previous keyboard character ready
	jmp coninf ;get character externally
	;ret
;
conech:
	LXI H,STA$RET
	PUSH H
CONECH0:
	;bd$read character with echo
	call bd$conin
	call echoc
	JC CONECH1 ;echo character?
        ;character must be echoed before return
	push psw
	mov c,a
	call tabout
	pop psw
	RET
CONECH1:
	CALL TEST$CTLS$MODE
	RNZ
	CPI CTLS
	JNZ CONECH2
	CALL CONBRK2
	JMP CONECH0
CONECH2:
	CPI CTLQ
	JZ CONECH0
	CPI CTLP
	JZ CONECH0
	RET
;
echoc:
	;echo character if graphic
	;cr, lf, tab, or backspace
	cpi cr
	rz ;carriage return?
	cpi lf
	rz ;line feed?
	cpi tab
	rz ;tab?
	cpi ctlh
	rz ;backspace?
	cpi ' '
	ret ;carry set if not graphic
;
CONSTX:
	LDA KBCHAR
	ORA A
	JNZ CONB1
	CALL CONSTF
	ANI 1
	RET
;
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

SET$CTLS$MODE:
	;SET CTLS STATUS OR INPUT FLAG FOR QUEUE MANAGER
	LXI H,QFLAG
	MVI M,40H
	XTHL
	PCHL

; CPM3_SD81: [endif] (linea 908)
;
TEST$CTLS$MODE:
	;RETURN WITH Z FLAG RESET IF CTL-S CTL-Q CHECKING DISABLED
	MOV B,A
	LDA CONMODE
	ANI 2
	MOV A,B
	RET
;
conbrk:	;check for character ready
	CALL TEST$CTLS$MODE
	JNZ CONSTX
	lda kbchar
	ora a
	jnz CONBRK1 ;skip if active kbchar
		;no active kbchar, check external break
		;DOES BIOS HAVE TYPE AHEAD?
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		LDA TYPE$AHEAD
	INR A
	JZ CONSTX ;YES
; CPM3_SD81: [endif] (linea 930)
		;CONBRKX CALLED BY CONOUT

	CONBRKX:
		;HAS CTL-S INTERCEPT BEEN DISABLED?
		CALL TEST$CTLS$MODE
	RNZ ;YES
		;DOES KBCHAR CONTAIN CTL-S?
		LDA KBCHAR
	CPI CTLS
	JZ CONBRK1 ;YES
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		CALL SET$CTLS$MODE
; CPM3_SD81: [endif] (linea 943)
		;IS A CHARACTER READY FOR INPUT?
		call constf
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		POP H
	MVI M,0
; CPM3_SD81: [endif] (linea 949)
		ani 1
	rz ;NO
		;character ready, bd$read it
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		CALL SET$CTLS$MODE
; CPM3_SD81: [endif] (linea 955)
		call coninf
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		POP H
	MVI M,0
; CPM3_SD81: [endif] (linea 960)
	CONBRK1:
		cpi ctls
	jnz conb0 ;check stop screen function
		;DOES KBCHAR CONTAIN A CTL-S?
		LXI H,KBCHAR
	CMP M
	JNZ CONBRK2 ;NO
		MVI M,0 ; KBCHAR = 0
		;found ctls, bd$read next character
	CONBRK2:

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		CALL SET$CTLS$MODE
; CPM3_SD81: [endif] (linea 974)
		call coninf ;to A
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		POP H
	MVI M,0
; CPM3_SD81: [endif] (linea 979)
		cpi ctlc
	JNZ CONBRK3
		LDA CONMODE
	ANI 08H
	JZ REBOOTX
		XRA A
	CONBRK3:
		SUI CTLQ
	RZ ; RETURN WITH A = ZERO IF CTLQ
		INR A
	CALL CONB3
	JMP CONBRK2
	conb0:
		LXI H,KBCHAR

		MOV B,A
		;IS CONMODE(1) TRUE?
		LDA CONMODE
	RAR
	JNC $+7 ;NO
		;DOES KBCHAR = CTLC?
		MVI A,CTLC
	CMP M
	RZ ;YES - RETURN
		MOV A,B

		CPI CTLQ
	JZ CONB2
		CPI CTLP
	JZ CONB2
		;character in accum, save it
		MOV M,A
	conb1:
		;return with bd$true set in accumulator
		mvi a,1
	ret
	CONB2:
		XRA A
	MOV M,A
	RET
	CONB3:
		CZ TOGGLE$LISTCP
		MVI C,7
	CNZ CONOUTF
		RET
;
TOGGLE$LISTCP:
	; IS PRINTER ECHO DISABLED?
	LDA CONMODE
	ANI 14H
	JNZ TOGGLE$L1 ;YES
	LXI H,LISTCP
	MVI A,1
	XRA M
	ANI 1
	MOV M,A
	RET
TOGGLE$L1:
	XRA A
	RET
;
QCONOUTF:
	;DOES FX = INPUT?
	LDA FX
	DCR A
	JZ CONOUTF ;YES
	;IS ESCAPE SEQUENCE DECODING IN EFFECT?
	MOV A,B
;;;	ANI 8		;[JCE] DRI Patch 13
	ANI 10h
	JNZ SCONOUTF ;YES
	JMP CONOUTF
;
bd$conout:
	;compute character position/bd$write console char from C
	;compcol = bd$true if computing column position
	lda compcol
	ora a
	jnz compout
		;bd$write the character, then compute the column
		;bd$write console character from C
		;B ~= 0 -> ESCAPE SEQUENCE DECODING
		LDA CONMODE
	ANI 14H
	MOV B,A
		push b
		;CALL CONBRKX FOR OUTPUT FUNCTIONS ONLY
		LDA FX
	DCR A
	CNZ CONBRKX
		pop b
	push b ;recall/save character
		call QCONOUTF ;externally, to console
		pop b
		;SKIP ECHO WHEN CONMODE & 14H ~= 0
		MOV A,B
	ORA A
	JNZ COMPOUT
		push b ;recall/save character
		;may be copying to the list device
		lda listcp
	ora a
	cnz listf ;to printer, if so
		pop b ;recall the character
	compout:
		mov a,c ;recall the character
		;and compute column position
		lxi h,column ;A = char, HL = .column
		cpi rubout
	rz ;no column change if nulls
		inr m ;column = column + 1
		cpi ' '
	rnc ;return if graphic
		;not graphic, reset column position
		dcr m ;column = column - 1
		mov a,m
	ora a
	rz ;return if at zero
		;not at zero, may be backspace or end line
		mov a,c ;character back to A
		cpi ctlh
	jnz notbacksp
			;backspace character
			dcr m ;column = column - 1
			ret
		notbacksp:
			;not a backspace character, eol?
			cpi cr
	rnz ;return if not
			;end of line, column = 0
			mvi m,0 ;column = 0
		ret
;
ctlout:
	;send C character with possible preceding up-arrow
	mov a,c
	call echoc ;cy if not graphic (or special case)
	jnc tabout ;skip if graphic, tab, cr, lf, or ctlh
		;send preceding up arrow
		push psw
	mvi c,ctl
	call bd$conout ;up arrow
		pop psw
	ori 40h ;becomes graphic letter
		mov c,a ;ready to print
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		call chk$column
	rz
; CPM3_SD81: [endif] (linea 1128)
		;(drop through to tabout)
;
tabout:
	;IS FX AN INPUT FUNCTION?
	LDA FX
	DCR A
	JZ TABOUT1 ;YES - ALWAYS EXPAND TABS FOR ECHO
	;HAS TAB EXPANSION BEEN DISABLED OR
	;ESCAPE SEQUENCE DECODING BEEN ENABLED?
	LDA CONMODE
	ANI 14H
	JNZ CONOUT ;YES
TABOUT1:
	;expand tabs to console
	mov a,c
	cpi tab
	jnz bd$conout ;direct to bd$conout if not
		;tab encountered, move to next tab position
	tab0:

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		lda fx
	cpi 1
	jnz tab1
		call chk$column
	rz
	tab1:
; CPM3_SD81: [endif] (linea 1156)

		mvi c,' '
	call bd$conout ;another blank
		lda column
	ani 111b ;column mod 8 = 0 ?
		jnz tab0 ;back for another if not
	ret
;
;
backup:
	;back-up one screen position
	call pctlh

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	lda comchr
	cpi ctla
	rz
; CPM3_SD81: [endif] (linea 1174)

	mvi c,' '
	call conoutf
;	(drop through to pctlh)				;
pctlh:
	;send ctlh to console without affecting column count
	mvi c,ctlh
	jmp conoutf
	;ret
;
crlfp:
	;print #, cr, lf for ctlx, ctlu, ctlr functions
	;then move to strtcol (starting column)
	mvi c,'#'
	call bd$conout
	call crlf
	;column = 0, move to position strtcol
	crlfp0:
		lda column
	lxi h,strtcol
		cmp m
	rnc ;stop when column reaches strtcol
		mvi c,' '
	call bd$conout ;print blank
		jmp crlfp0
;;
;
crlf:
	;carriage return line feed sequence
	mvi c,cr
	call bd$conout
	mvi c,lf
	jmp bd$conout
	;ret
;
print:
	;print message until M(BC) = '$'
	LXI H,OUTDELIM
	ldax b
	CMP M
	rz ;stop on $
		;more to print
		inx b
	push b
	mov c,a ;char to C
		call tabout ;another character printed
		pop b
	jmp print
;
QCONIN:

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	lhld apos
	mov a,m
	sta ctla$sw
; CPM3_SD81: [endif] (linea 1230)
	;IS BUFFER ADDRESS = 0?
	LHLD CONBUFFADD
	MOV A,L
	ORA H
	JZ CONIN ;YES
	;IS CHARACTER IN BUFFER < 5?

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	call qconinx ; mov a,m with bank 1 switched in
; CPM3_SD81: [else] (linea 1240)
; CPM3_SD81: [endif] (linea 1242)

	INX H
	ORA A
	JNZ QCONIN1 ; NO
	LXI H,0
QCONIN1:
	SHLD CONBUFFADD
	SHLD CONBUFFLEN
	RNZ ; NO
	JMP CONIN

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	
chk$column:
	lda conwidth
	mov e,a
	lda column
	cmp e
	ret
;
expand:
	xchg
	lhld apos
	xchg
expand1:
	ldax d
	ora a
	rz
	inx d
	inx h
	mov m,a
	inr b
	jmp expand1
;
copy$xbuff:
	mov a,b
	ora a
	rz
	push b
	mov c,b
	push h
	xchg
	inx d
	lxi h,xbuff
	call move
	mvi m,0
	shld xpos
	pop h
	pop b
	ret
;
copy$cbuff:
	lda ccpflgs+1
	ral
	rnc
	lxi h,xbuff
	lxi d,cbuff
	inr c
	jnz copy$cbuff1
	xchg
	mov a,b
	ora a
	rz
	sta cbuff$len
	push d
	lxi b,copy$cbuff2
	push b
	mov b,a
copy$cbuff1:
	inr b
	mov c,b
	jmp move
copy$cbuff2:
	pop h
	dcx h
	mvi m,0
	ret
;
save$col:
	lda column
	sta save$column
	ret
;
clear$right:
	lda column
	lxi h,ctla$column
	cmp m
	rnc
	mvi c,20h
	call bd$conout
	jmp clear$right
;
reverse:
	lda save$column
	lxi h,column
	cmp m
	rnc
	mvi c,ctlh
	call bd$conout
	jmp reverse
;
chk$buffer$size:
	push b
	push h
	lhld apos
	mvi e,0
cbs1:
	mov a,m
	ora a
	jz cbs2
	inr e
	inx h
	jmp cbs1
cbs2:
	mov a,b
	add e
	cmp c
	push a
	mvi c,7
	cnc conoutf
	pop a
	pop h
	pop b
	rc
	pop d
	pop d
	jmp readnx
;
refresh:
	lda ctla$sw
	ora a
	rz
	lda comchr
	cpi ctla
	rz
	cpi ctlf
	rz
	cpi ctlw
	rz
refresh0:
	push h
	push b
	call save$col
	lhld apos
refresh1:
	mov a,m
	ora a
	jz refresh2
	mov c,a
	call chk$column
	jc refresh05
	mov a,e
	sta column
	jmp refresh2
refresh05:
	push h
	call ctlout
	pop h
	inx h
	jmp refresh1
refresh2:
	lda column
	sta new$ctla$col
refresh3:
	call clear$right
	call reverse
	lda new$ctla$col
	sta ctla$column
	pop b
	pop h
	ret
;
init$apos:
	lxi h,aposi
	shld apos
	xra a
	sta ctla$sw
	ret
;
init$xpos:
	lxi h,xbuff
	shld xpos
	ret
;
set$ctla$column:
	lxi h,ctla$sw
	mov a,m
	ora a
	rnz
	inr m
	lda column
	sta ctla$column
	ret
;
readi:
	call chk$column
	cnc crlf
	lda cbuff$len
	mov b,a
	mvi c,0
	call copy$cbuff
; CPM3_SD81: [else] (linea 1444)
; CPM3_SD81: [endif] (linea 1455)

bd$read:	;bd$read to info address (max length, current length, buffer)

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	call init$xpos
	call init$apos
readx:
	call refresh
	xra a
	sta ctlw$sw
readx1:

; CPM3_SD81: [endif] (linea 1468)

	MVI A,1
	STA FX
	lda column
	sta strtcol ;save start for ctl-x, ctl-h
	lhld info
	mov c,m
	inx h
	push h
	XRA A
	MOV B,A
	STA SAVEPOS
	CMP C
	JNZ $+4
	INR C
	;B = current buffer length,
	;C = maximum buffer length,
	;HL= next to fill - 1
	readnx:
		;bd$read next character, BC, HL active
		push b
	push h ;blen, cmax, HL saved
		readn0:

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
			lda ctlw$sw
	ora a
	cz qconin
nxtline:
			sta comchr
; CPM3_SD81: [else] (linea 1499)
; CPM3_SD81: [endif] (linea 1501)

			;ani 7fh ;mask parity bit
			pop h
	pop b ;reactivate counters
			cpi cr
	jz readen ;end of line?
			cpi lf
	jz readen ;also end of line

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
			cpi ctlf
	jnz not$ctlf
		do$ctlf:
			call chk$column
	dcr e
	cmp e
	jnc readnx
		do$ctlf0:
			xchg
	lhld apos
	mov a,m
	ora a
	jz ctlw$l15
			inx h
	shld apos
	xchg
	jmp notr
		not$ctlf:
			cpi ctlw
	jnz not$ctlw
		do$ctlw:
			xchg
	lhld apos
	mov a,m
	ora a
	jz ctlw$l1
			xchg
	call chk$column
	dcr e
	cmp e
	xchg
	jc ctlw$l0
			xchg
	call refresh0
	xchg
	jmp ctlw$l13
		ctlw$l0:
			lhld apos
	mov a,m
			inx h
	shld apos
	jmp ctlw$l3
		ctlw$l1:
			lxi h,ctla$sw
	mov a,m
	mvi m,0
			ora a
	jz ctlw$l2
		ctlw$l13:
			lxi h,ctlw$sw
	mvi m,0
		ctlw$l15:
			xchg
	jmp readnx
		ctlw$l2:
			lda ctlw$sw
	ora a
	jnz ctlw$l25
			mov a,b
	ora a
	jnz ctlw$l15
			call init$xpos
		ctlw$l25:
			lhld xpos
	mov a,m
	ora a
			sta ctlw$sw
	jz ctlw$l15
			inx h
	shld xpos
		ctlw$l3:
			lxi h,ctlw$sw
	mvi m,ctlw
			xchg
	jmp notr
		not$ctlw:
			cpi ctla
	jnz not$ctla
		do$ctla:
			;do we have any characters to back over?
			lda strtcol
	mov d,a
	lda column
	cmp d
			jz readnx
			sta compcol ;COL > 0
			mov a,b
	ora a
	jz linelen
			;characters remain in buffer, backup one
			dcr b ;remove one character
			;compcol > 0 marks repeat as length compute
			;backup one position in xbuff
			push h
			call set$ctla$column
			pop d
			lhld apos
	dcx h
			shld apos
	ldax d
	mov m,a
	xchg
	jmp linelen
		not$ctla:
			cpi ctlb
	jnz not$ctlb
		do$ctlb:
			lda save$pos
	cmp b
	jnz ctlb$l0
			mvi a,ctlw
	sta ctla$sw
			sta comchr
	jmp do$ctlw
		ctlb$l0:
			xchg
	lhld apos
	inr b
		ctlb$l1:
			dcr b
	lda save$pos
	cmp b
	jz ctlb$l2
			dcx h
	ldax d
	mov m,a
	dcx d
	jmp ctlb$l1
		ctlb$l2:
			shld apos
			push b
	push d
			call set$ctla$column
		ctlb$l3:
			lda column
	mov b,a
			lda strtcol
	cmp b
	jz read$n0
 			mvi c,ctlh
	call bd$conout
	jmp ctlb$l3
		not$ctlb:
			cpi ctlk
	jnz not$ctlk
			xchg
	lxi h,aposi
	shld apos
			xchg
	call refresh
			jmp readnx
		not$ctlk:
			cpi ctlg
	jnz not$ctlg
			lda ctla$sw
	ora a
	jz readnx
			jmp do$ctlf0
		not$ctlg:
; CPM3_SD81: [endif] (linea 1671)

			cpi ctlh
	jnz noth ;backspace?
			LDA CTLH$ACT
	INR A
	JZ DO$RUBOUT
		DO$CTLH:
			;do we have any characters to back over?
			LDA STRTCOL
	MOV D,A
	LDA COLUMN
	CMP D
			jz readnx
			STA COMPCOL ;COL > 0
			MOV A,B
	ORA A
	JZ $+4
			;characters remain in buffer, backup one
			dcr b ;remove one character
			;compcol > 0 marks repeat as length compute
			jmp linelen ;uses same code as repeat
		noth:
			;not a backspace
			cpi rubout
	jnz notrub ;rubout char?
			LDA RUBOUT$ACT
	INR A
	JZ DO$CTLH
		DO$RUBOUT:
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
			mvi a,rubout
	sta comchr
			lda ctla$sw
	ora a
	jnz do$ctlh
; CPM3_SD81: [endif] (linea 1707)
			;rubout encountered, rubout if possible
			mov a,b
	ora a
	jz readnx ;skip if len=0
			;buffer has characters, resend last char
			mov a,m
	dcr b
	dcx h ;A = last char
			;blen=blen-1, next to fill - 1 decremented
			jmp rdech1 ;act like this is an echo
		notrub:
			;not a rubout character, check end line
			cpi ctle
	jnz note ;physical end line?
			;yes, save active counters and force eol
			push b
	MOV A,B
	STA SAVE$POS
			push h
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
			lda ctla$sw
	ora a
	cnz clear$right
; CPM3_SD81: [endif] (linea 1731)
			call crlf
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
			call refresh
; CPM3_SD81: [endif] (linea 1735)
			xra a
	sta strtcol ;start position = 00
			jmp readn0 ;for another character
		note:
			;not end of line, list toggle?
			cpi ctlp
	jnz notp ;skip if not ctlp
			;list toggle - change parity
			push h ;save next to fill - 1
			PUSH B
			XRA A
	CALL CONB3
			POP B
			pop h
	jmp readnx ;for another char
		notp:
			;not a ctlp, line delete?
			cpi ctlx
	jnz notx
			pop h ;discard start position
			;loop while column > strtcol
			backx:
				lda strtcol
	lxi h,column
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
				cmp m
	jc backx1
				lhld apos
	mov a,m
	ora a
	jnz readx
				jmp bd$read
			    backx1:
; CPM3_SD81: [else] (linea 1769)
; CPM3_SD81: [endif] (linea 1772)
				dcr m ;column = column - 1
				call backup ;one position
				jmp backx
		notx:
			;not a control x, control u?
			;not control-X, control-U?
			cpi ctlu
	jnz notu ;skip if not
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
			xthl
	call copy$xbuff
	xthl
; CPM3_SD81: [endif] (linea 1785)
			;delete line (ctlu)
		do$ctlu:
			call crlfp ;physical eol
			pop h ;discard starting position
			jmp bd$read ;to start all over
		notu:
			;not line delete, repeat line?
			cpi ctlr
	jnz notr
			XRA A
	STA SAVEPOS
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
			xchg
	call init$apos
	xchg
			mov a,b
	ora a
	jz do$ctlu
			xchg
	lhld apos
	inr b
		ctlr$l1:
			dcr b
	jz ctlr$l2
			dcx h
	ldax d
	mov m,a
	dcx d
			jmp ctlr$l1
		ctlr$l2:
			shld apos
	push b
	push d
			call crlfp
	mvi a,ctlw
	sta ctlw$sw
			sta ctla$sw
	jmp readn0
; CPM3_SD81: [endif] (linea 1824)
		linelen:
			;repeat line, or compute line len (ctlh)
			;if compcol > 0
			push b
	call crlfp ;save line length
			pop b
	pop h
	push h
	push b
			;bcur, cmax active, beginning buff at HL
		rep0:
			mov a,b
	ora a
	jz rep1 ;count len to 00
			inx h
	mov c,m ;next to print
			DCR B
			POP D
	PUSH D
	MOV A,D
	SUB B
	MOV D,A
			push b
	push h ;count length down
			LDA SAVEPOS
	CMP D
	CC CTLOUT
			pop h
	pop b ;recall remaining count
			jmp rep0 ;for the next character
		rep1:
			;end of repeat, recall lengths
			;original BC still remains pushed
			push h ;save next to fill
			lda compcol
	ora a ;>0 if computing length
			jz readn0 ;for another char if so
			;column position computed for ctlh
			lxi h,column
	sub m ;diff > 0
			sta compcol ;count down below
			;move back compcol-column spaces
		backsp:
			;move back one more space
			call backup ;one space
			lxi h,compcol
	dcr m
			jnz backsp
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
			call refresh
; CPM3_SD81: [endif] (linea 1875)
			jmp readn0 ;for next character
		notr:
			;not a ctlr, place into buffer
			;IS BUFFER FULL?
			PUSH A
			MOV A,B
	CMP C
	JC RDECH0 ;NO
			;DISCARD CHARACTER AND RING BELL
			POP A
	PUSH B
	PUSH H
			MVI C,7
	CALL CONOUTF
	JMP READN0
		RDECH0:

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
			lda comchr
	cpi ctlg
	jz rdech05
			lda ctla$sw
	ora a
	cnz chk$buffer$size
		rdech05:
; CPM3_SD81: [endif] (linea 1901)

			POP A
			inx h
	mov m,a ;character filled to mem
			inr b ;blen = blen + 1
		rdech1:
			;look for a random control character
			push b
	push h ;active values saved
			mov c,a ;ready to print
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
			call save$col
; CPM3_SD81: [endif] (linea 1914)
			call ctlout ;may be up-arrow C
			pop h
	pop b
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
			lda comchr
	cpi ctlg
	jz do$ctlh
			cpi rubout
	jz rdech2
			call refresh
		rdech2:
; CPM3_SD81: [endif] (linea 1926)
			LDA CONMODE
	ANI 08H
;;;			JNZ NOTC	;[JCE] DRI Patch 13
			jnz patch$064b

			mov a,m ;recall char
			cpi ctlc ;set flags for reboot test
patch$064b:		mov a,b ;move length to A
			jnz notc ;skip if not a control c
			cpi 1 ;control C, must be length 1
			jz REBOOTX ;reboot if blen = 1
			;length not one, so skip reboot
		notc:
			;not reboot, are we at end of buffer?
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
			cmp c
	jnc buffer$full
; CPM3_SD81: [else] (linea 1944)
; CPM3_SD81: [endif] (linea 1946)

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
			push b
	push h
			call chk$column
	jc readn0
			lda ctla$sw
	ora a
	jz do$new$line
			lda comchr
	cpi ctlw
	jz back$one
			cpi ctlf
	jz back$one
				
		do$newline:
			mvi a,ctle
	jmp nxtline

		back$one:
			;back up to previous character
			pop h
	pop b
			dcr b
	xchg
			lhld apos
	dcx h
	shld apos
			ldax d
	mov m,a
	xchg
	dcx h
			push b
	push h
	call reverse
			;disable ctlb or ctlw
			xra a
	sta ctlw$sw
	jmp readn0
		
		buffer$full:
			xra a
	sta ctlw$sw
	jmp readnx
; CPM3_SD81: [endif] (linea 1991)
		readen:
			;end of bd$read operation, store blen
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
			call expand
; CPM3_SD81: [endif] (linea 1996)
			pop h
	mov m,b ;M(current len) = B
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
			push b
			call copy$xbuff
			pop b
			mvi c,0ffh
	call copy$cbuff
; CPM3_SD81: [endif] (linea 2005)
			LXI H,0
	SHLD CONBUFFADD
			mvi c,cr
	jmp bd$conout ;return carriage
			;ret
;
func1	equ	CONECH
	;return console character with echo
;
func2:	equ	tabout
	;bd$write console character with tab expansion
;
func3:
	;return reader character
	call readerf
	jmp sta$ret
;
;func4:	equated to punchf
	;bd$write punch character
;
;func5:	equated to listf
	;bd$write list character
	;bd$write to list device
;
func6:
	;direct console i/o - bd$read if 0ffh
	mov a,c
	inr a
	jz dirinp ;0ffh => 00h, means input mode
		inr a
	JZ DIRSTAT ;0feh => direct STATUS function
		INR A
	JZ DIRINP1 ;0fdh => direct input, no status
		JMP CONOUTF
	DIRSTAT:
		;0feH in C for status
		CALL CONSTX
	JNZ LRET$EQ$FF
	JMP STA$RET
	dirinp:
		CALL CONSTX ;status check
		ora a
	RZ ;skip, return 00 if not ready
		;character is ready, get it
	dirinp1:
		call CONIN ;to A
		jmp sta$ret
;
func7:
	call auxinstf
	jmp sta$ret
;
func8:
	call auxoutstf
	jmp sta$ret
;
func9:
	;bd$write line until $ encountered
	xchg	;was lhld info	
	mov c,l
	mov b,h ;BC=string address
	jmp print ;out to console	

func10	equ	readi
	;bd$read a buffered console line

func11:
	;IS CONMODE(1) TRUE?
	LDA CONMODE
	RAR
	JNC NORMAL$STATUS ;NO
	;CTL-C ONLY STATUS CHECK
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	LXI H,QFLAG
	MVI M,80H
	PUSH H
; CPM3_SD81: [endif] (linea 2082)
	LXI H,CTLC$STAT$RET
	PUSH H
	;DOES KBCHAR = CTL-C?
	LDA KBCHAR
	CPI CTLC
	JZ CONB1 ;YES
	;IS THERE A READY CHARACTER?
	CALL CONSTF
	ORA A
	RZ ;NO
	;IS THE READY CHARACTER A CTL-C?
	CALL CONINF
	CPI CTLC
	JZ CONB0 ;YES
	STA KBCHAR
	XRA A
	RET

CTLC$STAT$RET:

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	CALL STA$RET
	POP H
	MVI M,0
	RET
; CPM3_SD81: [else] (linea 2108)
; CPM3_SD81: [endif] (linea 2110)

NORMAL$STATUS:
	;check console status
	call conbrk
	;(drop through to sta$ret)
sta$ret:
	;store the A register to aret
	sta aret
func$ret:						;
	ret ;jmp goback (pop stack for non cp/m functions)
;
setlret1:
	;set lret = 1
	mvi a,1
	jmp sta$ret				;
;
FUNC109:			;GET/SET CONSOLE MODE
	;DOES DE = 0FFFFH?
	MOV A,D
	ANA E
	INR A
	LHLD CONMODE
	JZ STHL$RET ;YES - RETURN CONSOLE MODE
	XCHG
	SHLD CONMODE
	RET ;NO - SET CONSOLE MODE
;
FUNC110:			;GET/SET FUNCTION 9 DELIMITER
	LXI H,OUT$DELIM
	;DOES DE = 0FFFFH?
	MOV A,D
	ANA E
	INR A
	MOV A,M
	JZ STA$RET ;YES - RETURN DELIMITER
	MOV M,E
	RET ;NO - SET DELIMITER
;
FUNC111:			;PRINT BLOCK TO CONSOLE
FUNC112:			;LIST BLOCK
	XCHG
	MOV E,M
	INX H
	MOV D,M
	INX H
	MOV C,M
	INX H
	MOV B,M
	XCHG
	;HL = ADDR OF STRING
	;BC = LENGTH OF STRING
BLK$OUT:
	MOV A,B
	ORA C
	RZ
	PUSH B
	PUSH H
	MOV C,M
	LDA FX
	CPI 111
	JZ BLK$OUT1
	CALL LISTF
	JMP BLK$OUT2
BLK$OUT1:
	CALL TABOUT
BLK$OUT2:
	POP H
	INX H
	POP B
	DCX B
	JMP BLK$OUT

SCONOUTF	EQU	CONOUTF

;
;	data areas
;
compcol:db	0	;bd$true if computing column position
strtcol:db	0	;starting column position after bd$read

; CPM3_SD81: [if not BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 2195)

SAVEPOS:DB	0	;POSITION IN BUFFER CORRESPONDING TO
			;BEGINNING OF LINE
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

comchr:		db	0
cbuff$len:	db	0
cbuff:		ds	256
		db	0
xbuff:		db	0
		ds	354
aposi:		db	0
xpos:		dw	0
apos:		dw	0
ctla$sw:	db	0
ctlw$sw:	db	0
save$column:	db	0
ctla$column:	db	0
new$ctla$col:	db	0

; CPM3_SD81: [endif] (linea 2216)

;	end of BDOS Console module
;
;**********************************************************************
;*****************************************************************
;
;	Error Messages

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

md	equ	0

; CPM3_SD81: [else] (linea 2229)
; CPM3_SD81: [endif] (linea 2233)

dskmsg: db	'CP/M Error On '
dskerr: db	' : ',md
permsg: db	'Disk I/O',md
selmsg: db	'Invalid Drive',md
rofmsg: db	'Read/Only File',md
rodmsg: db	'Read/Only Disk',md

; CPM3_SD81: [if not MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

passmsg:

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	db	'Password Error',md
; CPM3_SD81: [endif] (linea 2248)

fxstsmsg:
	db	'File Exists',md

wildmsg:
	db	'? in Filename',md

; CPM3_SD81: [endif] (linea 2256)
; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 2267)

;*****************************************************************
;*****************************************************************
;
;	common values shared between bdosi and bdos

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 2278)

aret:	ds	2	; address value to return
lret	equ	aret	; low(aret)

;*****************************************************************
;*****************************************************************
;**								**
;**   b a s i c    d i s k   o p e r a t i n g	 s y s t e m	**
;**								**
;*****************************************************************
;*****************************************************************

;	literal constants

bd$true	equ	0ffh	; constant bd$true
bd$false	equ	000h	; constant bd$false
enddir	equ	0ffffh	; end of directory
byte	equ	1	; number of bytes for "byte" type
word	equ	2	; number of bytes for "word" type

;	fixed addresses in low memory

tfcb	equ	005ch	; default fcb location
tbuff	equ	0080h	; default buffer location

;	error message handlers

rod$error:
	; report bd$read/only disk error
	mvi c,2
	jmp goerr

rof$error:
	; report bd$read/only file error
	mvi c,3
	jmp goerr

sel$error:
	; report select error
	mvi c,4
	; Invalidate curdsk to force select call
	; at next curselect call
	mvi a,0ffh
	sta curdsk

goerr:
	; hl = .errorhandler, call subroutine
	mov h,c
	mvi l,0ffh
	shld aret

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 2336)

goerr1:
	lda adrive
	sta errdrv
	lda error$mode
	inr a
	cnz error
; CPM3_SD81: [endif] (linea 2344)

rtn$phy$errs:

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 2352)

	; Return 0ffffh if fx = 27 or 31

	lda fx
	cpi 27
	jz goback0
	cpi 31
	jz goback0
	jmp goback

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 2373)

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

set$copy$cr$only:
	lda copy$cr$init
	sta copy$cr$only
	ret

reset$copy$cr$only:
	xra a
	sta copy$cr$init
	sta copy$cr$only
	ret

; CPM3_SD81: [endif] (linea 2388)

bde$e$bde$m$hl:
	mov a,e
	sub l
	mov e,a
	mov a,d
	sbb h
	mov d,a
	rnc
	dcr b
	ret

bde$e$bde$p$hl:
	mov a,e
	add l
	mov e,a
	mov a,d
	adc h
	mov d,a
	rnc
	inr b
	ret

shl3bv:
	inr c
shl3bv1:
	dcr c
	rz
	dad h
	adc a
	jmp shl3bv1

incr$rr:
	call get$rra
	inr m
	rnz
	inx h
	inr m
	rnz
	inx h
	inr m
	ret

save$rr:
	call save$rr2
	xchg
save$rr1:
	mvi c,3
	jmp move ; ret
save$rr2:
	call get$rra
	lxi d,save$ranr
	ret

reset$rr:
	call save$rr2
	jmp save$rr1 ; ret

compare:
	ldax d
	cmp m
	rnz
	inx h
	inx d
	dcr c
	rz
	jmp compare

;
;	local subroutines for bios interface
;

move:
	; Move data length of length c from source de to
	; destination given by hl
	inr c ; in case it is zero
	move0:
		dcr c
	rz ; more to move
		ldax d
	mov m,a ; one byte moved
		inx d
	inx h ; to next byte
		jmp move0

selectdisk:
	; Select the disk drive given by register D, and fill
	; the base addresses curtrka - alloca, then fill
	; the values of the disk parameter block
	mov c,d ; current disk# to c
	; lsb of e = 0 if not yet logged - in
	call seldskf ; hl filled by call
	; hl = 0000 if error, otherwise disk headers
	mov a,h
	ora l
	rz ; Return with C flag reset if select error
		; Disk header block address in hl
		mov e,m
	inx h
	mov d,m
	inx h ; de=.tran
		shld cdrmaxa
	inx h
	inx h ; .cdrmax
		shld curtrka
	inx h
	inx h ; hl=.currec
		shld curreca
	inx h
	inx h ; hl=.buffa
		inx h
	shld drvlbla
	inx h
		shld lsn$add
	inx h
	inx h
		; de still contains .tran
		xchg
	shld tranv ; .tran vector
		lxi h,dpbaddr ; de= source for move, hl=dest
		mvi c,addlist
	call move ; addlist filled
		; Now fill the disk parameter block
		lhld dpbaddr
	xchg ; de is source
		lxi h,sectpt ; hl is destination
		mvi c,dpblist
	call move ; data filled
		; Now set single/double map mode
		lhld maxall ; largest allocation number
		mov a,h ; 00 indicates < 255
		lxi h,single
	mvi m,bd$true ; Assume a=00
		ora a
	jz retselect
		; high order of maxall not zero, use double dm
		mvi m,bd$false
	retselect:
		; C flag set indicates successful select
		stc
	ret

bd$home:
	; Move to bd$home position, then offset to start of dir
	call homef
	xra a ; constant zero to accumulator
	lhld curtrka
	mov m,a
	inx h
	mov m,a ; curtrk=0000
	lhld curreca
	mov m,a
	inx h
	mov m,a ; currec=0000
	inx h
	mov m,a ; currec high byte=00

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 2549)

	ret

rdbuff:
	; Read buffer and check condition
	mvi a,1
	sta readf$sw
	call readf ; current drive, track, sector, dma
	jmp diocomp ; Check for i/o errors

wrbuff:
	; Write buffer and check condition
	; bd$write type (wrtype) is in register c
	xra a
	sta readf$sw
	call writef ; current drive, track, sector, dma
diocomp: ; Check for disk errors
	ora a
	rz
	mov c,a
	call chk$media$flag
	mov a,c
	cpi 3
	jc goerr
	mvi c,1
	jmp goerr

chk$media$flag:
	; A = 0ffh -> media changed
	inr a
	rnz

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	; Handle media changes as I/O errors for
	; permanent drives
	call chksiz$eq$8000h
	rz
; CPM3_SD81: [endif] (linea 2587)

	; BIOS says media change occurred
	; Is disk logged-in?
	lhld dlog
	call test$vector
	mvi c,1
	rz ; no - return error
	call media$change
	pop h ; Discard return address
	; Was this a bd$flush operation (fx = 48)?
	lda fx
	cpi 48
	rz ; yes
	; Is this a bd$flush to another drive?
	lxi h,adrive
	lda bd$seldsk
	cmp m
	jnz reset$relog
	; Bail out if fx = bd$read, bd$write, close, or search next
	call chk$exit$fxs
	; Is this a directory bd$read operation?
	lda readf$sw
	ora a
	rnz ; yes
	; Error - directory bd$write operation
	mvi c,2
	jmp goerr ; Return disk bd$read/only error

reset$relog:
	; Reset relog if flushing to another drive
	xra a
	sta relog
	ret

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

chksiz$eq$8000h:
	; Return with Z flag set if drive permanent
	; with no checksum vector
	lhld chksiz
	mvi a,80h
	cmp h
	rnz
	xra a
	cmp l
	ret

; CPM3_SD81: [endif] (linea 2635)

seekdir:
	; Seek the record containing the current dir entry

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 2657)

	lhld dcnt ; directory counter to hl
	mvi c,dskshf
	call hlrotr ; value to hl
	shld drec

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 2678)
	mvi b,0
	xchg
; CPM3_SD81: [endif] (linea 2681)

set$arecord:
	lxi h,arecord
	mov m,e
	inx h
	mov m,d
	inx h
	mov m,b
	ret

seek:
	; Seek the track given by arecord (actual record)

	lhld curtrka
	mov c,m
	inx h
	mov b,m ; bc = curtrk
	push b ; s0 = curtrk
	lhld curreca
	mov e,m
	inx h
	mov d,m
	inx h
	mov b,m ; bde = currec
	lhld arecord
	lda arecord+2
	mov c,a ; chl = arecord
seek0:
	mov a,l
	sub e
	mov a,h
	sbb d
	mov a,c
	sbb b
	push h ; Save low(arecord)
	jnc seek1 ; if arecord >= currec then go to seek1
	lhld sectpt
	call bde$e$bde$m$hl ; currec = currec - sectpt
	pop h
	xthl
	dcx h
	xthl ; curtrk = curtrk - 1
	jmp seek0
seek1:
	lhld sectpt
	call bde$e$bde$p$hl ; currec = currec + sectpt
	pop h ; Restore low(arecord)
	mov a,l
	sub e
	mov a,h
	sbb d
	mov a,c
	sbb b
	jc seek2 ; if arecord < currec then go to seek2
	xthl
	inx h
	xthl ; curtrk = curtrk + 1
	push h ; save low (arecord)
	jmp seek1
seek2:
	xthl
	push h ; hl,s0 = curtrk, s1 = low(arecord)
	lhld sectpt
	call bde$e$bde$m$hl ; currec = currec - sectpt
	pop h
	push d
	push b
	push h ; hl,s0 = curtrk,
	; s1 = high(arecord,currec), s2 = low(currec),
	; s3 = low(arecord)
	xchg
	lhld offset
	dad d
	mov b,h
	mov c,l
	shld track
	call settrkf ; call bios settrk routine
	; Store curtrk
	pop d
	lhld curtrka
	mov m,e
	inx h
	mov m,d
	; Store currec
	pop b
	pop d
	
	lhld curreca
	mov m,e
	inx h
	mov m,d
	inx h
	mov m,b ; currec = bde
	pop b ; bc = low(arecord), de = low(currec)
	mov a,c
	sub e
	mov l,a ; hl = bc - de
	mov a,b
	sbb d
	mov h,a
	call shr$physhf
	mov b,h
	mov c,l

	lhld tranv
	xchg ; bc=sector#, de=.tran
	call sectran ; hl = tran(sector)
	mov c,l
	mov b,h ; bc = tran(sector)
	shld sector
	call setsecf ; sector selected
	lhld curdma
	mov c,l
	mov b,h
	jmp setdmaf
	; ret
shr$physhf:
	lda physhf
	mov c,a
	jmp hlrotr

;	file control block (fcb) constants

empty	equ	0e5h	; empty directory entry
lstrec	equ	127	; last record# on extent
recsiz	equ	128	; record size
fcblen	equ	32	; file control block size
dirrec	equ	recsiz/fcblen	; directory fcbs / record
dskshf	equ	2	; log2(dirrec)
dskmsk	equ	dirrec-1
fcbshf	equ	5	; log2(fcblen)

extnum	equ	12	; extent number field
maxext	equ	31	; largest extent number
ubytes	equ	13	; unfilled bytes field
modnum	equ	14	; data module number

maxmod	equ	64	; largest module number

fwfmsk	equ	80h	; file bd$write flag is high order modnum
namlen	equ	15	; name length
reccnt	equ	15	; record count field
dskmap	equ	16	; disk map field
lstfcb	equ	fcblen-1
nxtrec	equ	fcblen
ranrec	equ	nxtrec+1; random record field (2 bytes)

;	reserved file indicators

rofile	equ	9	; high order of first type char
invis	equ	10	; invisible file in dir command

;	utility functions for file access

dm$position:
	; Compute disk map position for vrecord to hl
	lxi h,blkshf
	mov c,m ; shift count to c
	lda vrecord ; current virtual record to a
	dmpos0:
		ora a
	rar
	dcr c
	jnz dmpos0
	; a = shr(vrecord,blkshf) = vrecord/2**(sect/block)
	mov b,a ; Save it for later addition
	mvi a,8
	sub m ; 8-blkshf to accumulator
	mov c,a ; extent shift count in register c
	lda extval ; extent value ani extmsk
	dmpos1:
		; blkshf = 3,4,5,6,7, c=5,4,3,2,1
		; shift is 4,3,2,1,0
		dcr c
	jz dmpos2
		ora a
	ral
	jmp dmpos1
	dmpos2:
	; Arrive here with a = shl(ext and extmsk,7-blkshf)
	add b ; Add the previous shr(vrecord,blkshf) value
	; a is one of the following values, depending upon alloc
	; bks blkshf
	; 1k   3     v/8 + extval * 16
	; 2k   4     v/16+ extval * 8
	; 4k   5     v/32+ extval * 4
	; 8k   6     v/64+ extval * 2
	; 16k  7     v/128+extval * 1
	ret ; with dm$position in a

getdma:
	lhld info
	lxi d,dskmap
	dad d
	ret

getdm:
	; Return disk map value from position given by bc
	call getdma
	dad b ; Index by a single byte value
	lda single ; single byte/map entry?
	ora a
	jz getdmd ; Get disk map single byte
		mov l,m
	mov h,b
	ret ; with hl=00bb
	getdmd:
		dad b ; hl=.fcb(dm+i*2)
		; double precision value returned
		mov a,m
	inx h
	mov h,m
	mov l,a
	ret

index:
	; Compute disk block number from current fcb
	call dm$position ; 0...15 in register a
	sta dminx
	mov c,a
	mvi b,0
	call getdm ; value to hl
	shld arecord
	mov a,l
	ora h
	ret

atran:
	; Compute actual record address, assuming index called

;	arecord = shl(arecord,blkshf)

	lda blkshf
	mov c,a
	lhld arecord
	xra a
	call shl3bv
	shld arecord
	sta arecord+2

	shld arecord1 ; Save low(arecord)

;	arecord = arecord or (vrecord and blkmsk)

	lda blkmsk
	mov c,a
	lda vrecord
	ana c
	mov b,a ; Save vrecord & blkmsk in reg b & blk$off
	sta blk$off
	lxi h,arecord
	ora m
	mov m,a
	ret

get$atts:
	; Get volatile attributes starting at f'5
	; info locates fcb
	lhld info
	lxi d,8
	dad d ; hl = .fcb(f'8)
	mvi c,4
get$atts$loop:
	mov a,m
	add a
	push a
	mov a,d
	rar
	mov d,a
	pop a
	rrc
	mov m,a
	dcx h
	dcr c
	jnz get$atts$loop
	mov a,d
	ret

get$s1:
	; Get current s1 field to a
	call getexta
	inx h
	mov a,m
	ret

get$rra:
	; Get current ran rec field address to hl
	lhld info
	lxi d,ranrec
	dad d ; hl=.fcb(ranrec)
	ret

getexta:
	; Get current extent field address to hl
	lhld info
	lxi d,extnum
	dad d ; hl=.fcb(extnum)
	ret

getrcnta:
	; Get reccnt address to hl
	lhld info
	lxi d,reccnt
	dad d
	ret

getfcba:
	; Compute reccnt and nxtrec addresses for get/setfcb
	call getrcnta
	xchg ; de=.fcb(reccnt)
	lxi h,(nxtrec-reccnt)
	dad d ; hl=.fcb(nxtrec)
	ret

getfcb:
	; Set variables from currently addressed fcb
	call getfcba ; addresses in de, hl
	mov a,m
	sta vrecord ; vrecord=fcb(nxtrec)
	xchg
	mov a,m
	ora a
	jnz getfcb0
	call get$dir$ext
	mov c,a
	call set$rc
	mov a,m
getfcb0:
	cpi 81h
	jc getfcb1
	mvi a,80h
getfcb1:
	sta rcount ; rcount=fcb(reccnt) or 80h
	call getexta ; hl=.fcb(extnum)
	lda extmsk ; extent mask to a
	ana m ; fcb(extnum) and extmsk
	sta extval
	ret

setfcb:
	; Place values back into current fcb
	call getfcba ; addresses to de, hl
	; fcb(cr) = vrecord
	lda vrecord
	mov m,a
	; Is fx < 22? (sequential bd$read or bd$write)
	lda fx
	cpi 22
	jnc $+4 ; no
	; fcb(cr) = fcb(cr) + 1
	inr m
	xchg
	mov a,m
	cpi 80h
	rnc ; dont reset fcb(rc) if > 7fh
	lda rcount
	mov m,a ; fcb(reccnt)=rcount
	ret

zero$ext$mod:
	call getexta
	mov m,d
	inx h
	inx h
	mov m,d
	ret

zero:
	mov m,b
	inx h
	dcr c
	rz
	jmp zero

hlrotr:
	; hl rotate right by amount c
	inr c ; in case zero
	hlrotr0: dcr c
	rz ; return when zero
		mov a,h
	ora a
	rar
	mov h,a ; high byte
		mov a,l
	rar
	mov l,a ; low byte
		jmp hlrotr0

compute$cs:
	; Compute checksum for current directory buffer
	lhld buffa ; current directory buffer
	lxi b,4 ; b = 0, c = 4
compute$cs0:
	mvi d,32 ; size of fcb
	xra a ; clear checksum value
compute$cs1:
		add m
	inx h
	dcr d
		jnz compute$cs1
		xra b
	mov b,a
	dcr c
		jnz compute$cs0
	ret ; with checksum in a

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 3152)

check$fcb:

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 3193)
	call gets1
	lhld lsn$add
	cmp m
	cnz chk$media$fcb
; CPM3_SD81: [endif] (linea 3198)

chek$fcb:
	lda high$ext

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 3210)
	ora a
	rz
; CPM3_SD81: [endif] (linea 3213)

	lhld info
	xra a
	mov m,a ; fcb(0) = 0
chek$fcb1:

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 3222)
	ret

chk$media$fcb:
	; fcb(s1) ~= DPH login sequence # field
	; Is fcb addr < bdosadd?

; CPM3_SD81: [if banked] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	lhld user$info
; CPM3_SD81: [else] (linea 3231)
; CPM3_SD81: [endif] (linea 3233)

	xchg
	lhld bdosadd
	call subdh
	jnc chk$media1 ; no
	; Is rlog(drive) bd$true?
	lhld rlog
	call testvector
	rz ; no
chk$media1:
	; Return invalid fcb error code
	pop h
	pop h
chk$media2:
	mvi a,10
	jmp sta$ret
; CPM3_SD81: [endif] (linea 3250)

hlrotl:
	; Rotate the mask in hl by amount in c
	inr c ; may be zero
	hlrotl0: dcr c
	rz ; return if zero
		dad h
	jmp hlrotl0

set$dlog:
	lxi d,dlog
set$cdisk:
	; Set a "1" value in curdsk position of bc
	lda curdsk
set$cdisk1:
	mov c,a ; Ready parameter for shift
	lxi h,1 ; number to shift
	call hlrotl ; hl = mask to integrate
	ldax d
	ora l
	stax d
	inx d
	ldax d
	ora h
	stax d
	ret

nowrite:
	; Return bd$true if dir checksum difference occurred
	lhld rodsk

test$vector:
	lda curdsk
test$vector1:
	mov c,a
	call hlrotr
	mov a,l
	ani 1b
	ret ; non zero if curdsk bit on

check$rodir:
	; Check current directory element for bd$read/only status
	call getdptra ; address of element

check$rofile:
	; Check current buff(dptr) or fcb(0) for r/o status
	call ro$test
	rnc ; Return if not set
	jmp rof$error ; Exit to bd$read only disk message

ro$test:
	lxi d,rofile
	dad d
	mov a,m
	ral
	ret ; carry set if r/o

check$write:
	; Check for bd$write protected disk
	call nowrite
	rz ; ok to bd$write if not rodsk
	jmp rod$error ; bd$read only disk error

getdptra:
	; Compute the address of a directory element at
	; positon dptr in the buffer

	lhld buffa
	lda dptr
addh:
	; hl = hl + a
	add l
	mov l,a
	rnc
	; overflow to h
	inr h
	ret

getmodnum:
	; Compute the address of the module number
	; bring module number to accumulator
	; (high order bit is fwf (file bd$write flag)
	lhld info
	lxi d,modnum
	dad d ; hl=.fcb(modnum)
	mov a,m
	ret ; a=fcb(modnum)

clrmodnum:
	; Clear the module number field for user open/make
	call getmodnum
	mvi m,0 ; fcb(modnum)=0
	ret

clr$ext:
	; fcb ext = fcb ext & 1fh
	call getexta
	mov a,m
	ani 00011111b
	mov m,a
	
	ret

setfwf:
	call getmodnum ; hl=.fcb(modnum), a=fcb(modnum)
	; Set fwf (file bd$write flag) to "1"
	ori fwfmsk
	mov m,a ; fcb(modnum)=fcb(modnum) or 80h
	; also returns non zero in accumulator
	ret

compcdr:
	; Return cy if cdrmax > dcnt
	lhld dcnt
	xchg ; de = directory counter
	lhld cdrmaxa ; hl=.cdrmax
	mov a,e
	sub m ; low(dcnt) - low(cdrmax)
	inx h ; hl = .cdrmax+1
	mov a,d
	sbb m ; hig(dcnt) - hig(cdrmax)
	; condition dcnt - cdrmax  produces cy if cdrmax>dcnt
	ret

setcdr:
	; if not (cdrmax > dcnt) then cdrmax = dcnt+1
	call compcdr
	rc ; Return if cdrmax > dcnt
	; otherwise, hl = .cdrmax+1, de = dcnt
	inx d
	mov m,d
	dcx h
	mov m,e
	ret

subdh:
	; Compute hl = de - hl
	mov a,e
	sub l
	mov l,a
	mov a,d
	sbb h
	mov h,a
	ret

newchecksum:
	mvi c,0feh ; Drop through to compute new checksum
checksum:
	; Compute current checksum record and update the
	; directory element if c=bd$true, or check for = if not
	; drec < chksiz?
	lhld drec
	xchg
	lhld chksiz
	mov a,h
	ani 7fh
	mov h,a ; Mask off permanent drive bit
	call subdh ; de-hl
	rnc ; Skip checksum if past checksum vector size
		; drec < chksiz, so continue
		push b ; Save init flag
		call compute$cs ; Check sum value to a
		lhld checka ; address of check sum vector
		xchg
		lhld drec
		dad d ; hl = .check(drec)
		pop b ; Recall bd$true=0ffh or bd$false=00 to c
		inr c ; 0ffh produces zero flag
		jz initial$cs
		inr c ; 0feh produces zero flag
		jz update$cs

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 3426)

			; not initializing, compare
			cmp m ; compute$cs=check(drec)?
			rz ; no message if ok
			; checksum error, are we beyond
			; the end of the disk?
			call nowrite
;;;			rnz	;[JCE] DRI Patch 13
			nop

media$change:
			call discard$data

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 3442)
			mvi a,0ffh
	sta relog
	sta hashl
			call set$rlog
; CPM3_SD81: [endif] (linea 3447)

			; Reset the drive

			call set$dlog
	jmp reset37x

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 3459)

		initial$cs:
			; initializing the checksum
			cmp m
	mov m,a
	rz
			; or 1 into login seq # if media change
			lhld lsn$add
	mvi a,1
	ora m
	mov m,a
	ret

		update$cs:
			; updating the checksum
			mov m,a
	ret

set$ro:
	; Set current disk to bd$read/only
	lda bd$seldsk
	lxi d,rodsk
	call set$cdisk1 ; sets bit to 1
	; high water mark in directory goes to max
	lhld dirmax
	inx h
	xchg ; de = directory max
	lhld cdrmaxa ; hl = .cdrmax
	mov m,e
	inx h
	mov m,d ; cdrmax = dirmax
	ret

set$rlog:
	; rlog(bd$seldsk) = bd$true
	lhld olog
	call test$vector
	rz
	lxi d,rlog
	jmp set$cdisk

tst$log$fxs:
	lda chksiz+1
	ani 80h
	rnz
	lxi h,log$fxs
tst$log0:
	lda fx
	mov b,a
tst$log1:
	mov a,m
	cmp b
	rz
	inx h
	ora a
	jnz tst$log1
	inr a
	ret

test$media$flag:
	lhld lsn$add
	inx h
	mov a,m
	ora a
	ret

chk$exit$fxs:
	lxi h,goback
	push h
	; does fx = bd$read or bd$write function?
	; and is drive removable?
	lxi h,rw$fxs
	call tst$log0
	jz chk$media2 ; yes
	; is fx = close or searchn function?
	; and is drive removable?
	lxi h,sc$fxs
	call tst$log0
	jz lret$eq$ff ; yes
	pop h
	ret

tst$relog:
	lxi h,relog
	mov a,m
	ora a
	rz
	mvi m,0
drv$relog:
	call curselect
	lxi h,0
	shld dcnt
	xra a
	sta dptr
	ret

set$lsn:
	lhld lsn$add
	mov c,m
	call gets1
	mov m,c
	ret

discard$data$bcb:
	lhld dtabcba
	mvi c,4
	jmp discard0

discard$data:
	lhld dtabcba
	jmp discard

discard$dir:
	lhld dirbcba

discard:
	mvi c,1
discard0:
	mov a,l
	ana h
	inr a
	rz

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	mov e,m
	inx h
	mov d,m
	xchg
discard1:
	push h
	push b
	lxi d,adrive
	call compare
	pop b
	pop h
	jnz discard2

	mvi m,0ffh
discard2:
	lxi d,13
	dad d
	mov e,m
	inx h
	mov d,m
	xchg
	mov a,l
	ora h
	rz
	jmp discard1
; CPM3_SD81: [else] (linea 3609)
; CPM3_SD81: [endif] (linea 3617)

get$buffa:
	push d
	lxi d,10
	dad d
	mov e,m
	inx h
	mov d,m

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	inx h
	mov a,m
	sta buffer$bank
; CPM3_SD81: [endif] (linea 3631)

	xchg
	pop d
	ret

rddir:
	; Read a directory entry into the directory buffer
	call seek$dir
	mvi a,3
	jmp wrdir0

seek$copy:
wrdir:
	; Write the current directory entry, set checksum
	call check$write
	call newchecksum ; Initialize entry
	mvi a,5
wrdir0:
	lxi h,0
	shld last$block
	lhld dirbcba

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	cpi 5
	jnz $+6
	lhld curbcba
; CPM3_SD81: [endif] (linea 3658)

	call deblock

setdata:
	; Set data dma address
	lhld dmaad
	jmp bd$setdma ; to complete the call

setdir1:
	call get$buffa

bd$setdma:
	; hl=.dma address to set (i.e., buffa or dmaad)
	shld curdma
	ret

dir$to$user:

; CPM3_SD81: [if not MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	; Copy the directory entry to the user buffer
	; after call to search or searchn by user code
	lhld buffa
	xchg ; source is directory buffer
	lhld xdmaad ; destination is user dma address
	lxi b,recsiz ; copy entire record
	call movef
; CPM3_SD81: [endif] (linea 3685)
	; Set lret to dcnt & 3 if search successful
	lxi h,lret
	mov a,m
	inr a
	rz
	lda dcnt
	ani dskmsk
	mov m,a
	ret

make$fcb$inv: ; Flag fcb as invalid
	; Reset fcb bd$write flag
	call setfwf
	; Set 1st two bytes of diskmap to ffh
	inx h
	inx h
	mvi a,0ffh
	mov m,a
	inx h
	mov m,a
	ret

chk$inv$fcb: ; Check for invalid fcb
	call getdma
	jmp test$ffff

tst$inv$fcb: ; Test for invalid fcb
	call chk$inv$fcb
	rnz
	pop h
	mvi a,9
	jmp sta$ret
	; lret = 9

end$of$dir:
	; Return zero flag if at end of directory, non zero
	; if not at end (end of dir if dcnt = 0ffffh)
	lxi h,dcnt
test$ffff:
	mov a,m ; may be 0ffh
	inx h
	cmp m ; low(dcnt) = high(dcnt)?
	rnz ; non zero returned if different
	; high and low the same, = 0ffh?
	inr a ; 0ffh becomes 00 if so
	ret

set$end$dir:
	; Set dcnt to the end of the directory
	lxi h,enddir
	shld dcnt
	ret

read$dir:
	call r$dir
	jmp r$dir1

r$dir:
	; Read next directory entry, with c=bd$true if initializing

	lhld dirmax
	xchg ; in preparation for subtract
	lhld dcnt
	inx h
	shld dcnt ; dcnt=dcnt+1
	; Continue while dirmax >= dcnt (dirmax-dcnt no cy)
	call subdh ; de-hl

	jc set$end$dir

	read$dir0:
		; not at end of directory, seek next element
		; initialization flag is in c
		lda dcnt
	ani dskmsk ; low(dcnt) and dskmsk
		mvi b,fcbshf ; to multiply by fcb size
		read$dir1:
			add a
	dcr b
	jnz read$dir1
		; a = (low(dcnt) and dskmsk) shl fcbshf
		sta dptr ; ready for next dir operation
		ora a
	rnz ; Return if not a new record
	read$dir2:
		push b ; Save initialization flag c
		call rd$dir ; Read the directory record
		pop b ; Recall initialization flag
		lda relog
	ora a
	rnz
		jmp checksum ; Checksum the directory elt

r$dir2:
	call read$dir2
r$dir1:
	lda relog
	ora a
	rz
	call chk$exit$fxs
	call tst$relog
	jmp rd$dir

getallocbit:
	; Given allocation vector position bc, return with byte
	; containing bc shifted so that the least significant
	; bit is in the low order accumulator position.  hl is
	; the address of the byte for possible replacement in
	; memory upon return, and d contains the number of shifts
	; required to place the returned value back into position
	mov a,c
	ani 111b
	inr a
	mov e,a
	mov d,a
	; d and e both contain the number of bit positions to shift

	mov h,b
	mov l,c
	mvi c,3 ; bc = bc shr 3
	call hlrotr ; hlrotr does not touch d and e
	mov b,h
	mov c,l

	lhld alloca ; base address of allocation vector
	dad b
	mov a,m ; byte to a, hl = .alloc(bc shr 3)
	; Now move the bit to the low order position of a
	rotl: rlc
	dcr e
	jnz rotl
	ret

setallocbit:
	; bc is the bit position of alloc to set or reset.  the
	; value of the bit is in register e.
	push d
	call getallocbit ; shifted val a, count in d
	ani 11111110b ; mask low bit to zero (may be set)
	pop b
	ora c ; low bit of c is masked into a
	; jmp rotr ; to rotate back into proper position
	; ret

rotr:
	; byte value from alloc is in register a, with shift count
	; in register c (to place bit back into position), and
	; target alloc position in registers hl, rotate and replace
	rrc
	dcr d
	jnz rotr ; back into position
	mov m,a ; back to alloc
	ret

copy$alv:
	; If Z flag set, copy 1st ALV to 2nd
	; Otherwise, copy 2nd ALV to 1st

; CPM3_SD81: [if not BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 3849)

	push a
	call get$nalbs
	mov b,h
	mov c,l
	lhld alloca
	mov d,h
	mov e,l
	dad b
	pop a
	jz movef
	xchg
	jmp movef

scandm$ab:
	; Set/Reset 1st and 2nd ALV
	push b
	call scandm$a
	pop b
	;jmp scandm$b

scandm$b:
	; Set/Reset 2nd ALV

; CPM3_SD81: [if not BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 3878)

	push b
	call get$nalbs
	xchg
	lhld alloca
	pop b
	push h
	dad d
	shld alloca
	call scandm$a
	pop h
	shld alloca
	ret

scandm$a:
	; Set/Reset 1st ALV
	; Scan the disk map addressed by dptr for non-zero
	; entries, the allocation vector entry corresponding
	; to a non-zero entry is set to the value of c (0,1)
	call getdptra ; hl = buffa + dptr
	; hl addresses the beginning of the directory entry
	lxi d,dskmap
	dad d ; hl now addresses the disk map
	push b ; Save the 0/1 bit to set
	mvi c,fcblen-dskmap+1 ; size of single byte disk map + 1
	scandm0:
		; Loop once for each disk map entry
		pop d ; Recall bit parity
		dcr c
	rz ; all done scanning?
		; no, get next entry for scan
		push d ; Replace bit parity
		lda single
	ora a
	jz scandm1
			; single byte scan operation
			push b ; Save counter
			push h ; Save map address
			mov c,m
	mvi b,0 ; bc=block#
			jmp scandm2
		scandm1:
			; double byte scan operation
			dcr c ; count for double byte
			push b ; Save counter
			mov c,m
	inx h
	mov b,m ; bc=block#
			push h ; Save map address
		scandm2:
			; Arrive here with bc=block#, e=0/1
			mov a,c
	ora b ; Skip if = 0000
			jz scandm3
			lhld maxall ; Check invalid index
			mov a,l
	sub c
	mov a,h
	sbb b ; maxall - block#
			cnc set$alloc$bit
			; bit set to 0/1
		scandm3:
			pop h
	inx h ; to next bit position
			pop b ; Recall counter
			jmp scandm0 ; for another item

get$nalbs: ; Get # of allocation vector bytes
	lhld maxall
	mvi c,3
	; number of bytes in allocation vector is (maxall/8)+1
	call hlrotr
	inx h
	ret

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 3968)

initialize:
	; Initialize the current disk
	; lret = bd$false ; set to bd$true if $ file exists
	; Compute the length of the allocation vector - 2

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 3987)

	call test$media$flag 
	mvi m,0
;;;	call discard$data ;[JCE] DRI Patch 13 
;;;	call discard$dir

; CPM3_SD81: [endif] (linea 3994)
;[JCE] DRI Patch 13

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
;;;	; Is drive permanent with no chksum vector?
;;;	call chksiz$eq$8000h
;;;	jnz initialize2 ; no
;;;	; Is this an initial login operation?
;;;	; register A = 0
;;;	lhld lsn$add
;;;	cmp m
;;;	mvi m,2
;;;	call test$media$flag
;;;	mvi m,0 ; Reset media change flag
	call chksiz$eq$8000h
	jnz patch$13ff
	lhld lsn$add
	cmp m
	nop
	nop
	jz patch$13ff
	jmp patch$2d40

patch$13ff:

	call discard$data
	call discard$dir

initialize2:
; CPM3_SD81: [else] (linea 4023)
; CPM3_SD81: [endif] (linea 4027)

	call get$nalbs ; Get # of allocation vector bytes
	mov b,h
	mov c,l ; Count down bc til zero
	lhld alloca ; base of allocation vector
	; Fill the allocation vector with zeros
	initial0:
		mvi m,0
	inx h ; alloc(i)=0
		dcx b ; Count length down
		mov a,b
	ora c
	jnz initial0

	lhld drvlbla
	mov m,a ; Zero out drive desc byte

	; Set the reserved space for the directory

	lhld dirblk
	xchg
	lhld alloca ; hl=.alloc()
	mov m,e
	inx h
	mov m,d ; sets reserved directory blks
	; allocation vector initialized, bd$home disk
	call bd$home
	; cdrmax = 3 (scans at least one directory record)
	lhld cdrmaxa
	mvi m,4
	inx h
	mvi m,0

	call set$end$dir ; dcnt = enddir
	lhld hashtbla
	shld arecord1

	; Read directory entries and check for allocated storage

	initial2:
		mvi c,bd$true
	call read$dir
		call end$of$dir
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		jz patch$2d6a	;[JCE] DRI Patch 13
; CPM3_SD81: [else] (linea 4073)
; CPM3_SD81: [endif] (linea 4075)
		; not end of directory, valid entry?
		call getdptra ; hl = buffa + dptr
		xchg
	lhld arecord1
	mov a,h
	ana l
	inr a
	xchg
		; is hashtbla ~= 0ffffh
		cnz init$hash ; yes - call init$hash
		mvi a,21h
	cmp m
		jz initial2 ; Skip date & time records

		mvi a,empty
	cmp m
		jz initial2 ; go get another item

		mvi a,20h
	cmp m
	jz drv$lbl
		mvi a,10h
	ana m
	jnz initial3

		; Now scan the disk map for allocated blocks

		mvi c,1 ; set to allocated
		call scandm$a
	initial3:
		call setcdr ; set cdrmax to dcnt
		jmp initial2 ; for another entry

drv$lbl:
		lxi d,extnum
	dad d
	mov a,m
		lhld drvlbla
	mov m,a
	jmp initial3

copy$dirloc:
	; Copy directory location to lret following
	; delete, rename, ... ops

	lda dirloc
	jmp sta$ret
	; ret

compext:
	; Compare extent# in a with that in c, return nonzero
	; if they do not match
	push b ; Save c's original value
	push psw
	lda extmsk
	cma
	mov b,a
	; b has negated form of extent mask
	mov a,c
	ana b
	mov c,a ; low bits removed from c
	pop psw
	ana b ; low bits removed from a
	sub c
	ani maxext ; Set flags
	pop b ; Restore original values
	ret

get$dir$ext:
	; Compute directory extent from fcb
	; Scan fcb disk map backwards
	call getfcba ; hl = .fcb(vrecord)
	mvi c,16
	mov b,c
	inr c
	push b
	; b=dskmap pos (rel to 0)
get$de0:
	pop b
	dcr c
	xra a ; Compare to zero
get$de1:
	dcx h
	dcr b; Decr dskmap position
	cmp m
	jnz get$de2 ; fcb(dskmap(b)) ~= 0
	dcr c
	jnz get$de1
	; c = 0 -> all blocks = 0 in fcb disk map
get$de2:
	mov a,c
	sta dminx
	lda single
	ora a
	mov a,b
	jnz get$de3
	rar ; not single, divide blk idx by 2
get$de3:
	push b
	push h ; Save dskmap position & count
	mov l,a
	mvi h,0 ; hl = non-zero blk idx
	; Compute ext offset from last non-zero
	; block index by shifting blk idx right
	; 7 - blkshf
	lda blkshf
	mov d,a
	mvi a,7
	sub d
	mov c,a
	call hlrotr
	mov b,l
	; b = ext offset
	lda extmsk
	cmp b
	pop h
	jc get$de0
	; Verify computed extent offset <= extmsk
	call getexta
	mov c,m
	cma
	ani maxext
	ana c
	ora b
	; dir ext = (fcb ext & (~ extmsk) & maxext) | ext offset
	pop b ; Restore stack
	ret ; a = directory extent

searchi:
	; search initialization
	lhld info
	shld searcha ; searcha = info
searchi1:
	mov a,c
	sta searchl ; searchl = c
	call set$hash
	mvi a,0ffh
	sta dirloc ; changed if actually found
	ret

search$namlen:
	mvi c,namlen
	jmp search
search$extnum:
	mvi c,extnum
search:
	; Search for directory element of length c at info
	call searchi
search1: ; entry point used by rename
	call set$end$dir ; dcnt = enddir
	call tst$log$fxs
	cz bd$home
	; (drop through to searchn)

searchn:
	; Search for the next directory element, assuming
	; a previous call on search which sets searcha and
	; searchl

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 4241)
	xra a
	sta user0$pass
; CPM3_SD81: [endif] (linea 4244)

	call search$hash
	jnz search$fin
	mvi c,bd$false
	call read$dir ; Read next dir element
	call end$of$dir
	jz search$fin
		; not end of directory, scan for match
		lhld searcha
	xchg ; de=beginning of user fcb
		ldax d ; first character
		cpi empty ; Keep scanning if empty
		jz searchnext
		; not empty, may be end of logical directory
		push d ; Save search address
		call compcdr ; past logical end?
		pop d ; Recall address
		jnc search$fin ; artificial stop
searchnext:
		call getdptra ; hl = buffa+dptr
		lda searchl
	mov c,a ; length of search to c
		mvi b,0 ; b counts up, c counts down

		mov a,m
	cpi empty
	cz save$dcnt$pos1

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		xra a
	sta save$xfcb
		mov a,m
	ani 11101111b
	cmp m
	jz search$loop
		xchg
	cmp m
	xchg
	jnz search$loop
		lda find$xfcb
	ora a
	jz search$n
		sta save$xfcb
	jmp searchok
; CPM3_SD81: [endif] (linea 4289)

		searchloop:
			mov a,c
	ora a
	jz endsearch
			ldax d
	cpi '?'
	jz searchok ; ? in user fcb
			; Scan next character if not ubytes
			mov a,b
	cpi ubytes
	jz searchok
			; not the ubytes field, extent field?
			cpi extnum ; may be extent field
			jz searchext ; Skip to search extent
			cpi modnum
	ldax d
	cz searchmod
			sub m
	ani 7fh ; Mask-out flags/extent modulus
			jnz searchnm ; Skip if not matched
			jmp searchok ; matched character
		searchext:
			ldax d
			; Attempt an extent # match
			push b ; Save counters

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 4328)

			mov c,m ; directory character to c
			call compext ; Compare user/dir char

			mov b,a
			lda user0pass
	inr a
	jz save$dcnt$pos2
			; Disable search of user 0 if any fcb
			; is found under the current user #
			xra a
	sta search$user0
			mov a,b

			pop b ; Recall counters
			ora a ; Set flag
			jnz searchn ; Skip if no match
		searchok:
			; current character matches
			inx d
	inx h
	inr b
	dcr c
			jmp searchloop
		endsearch:
			; entire name matches, return dir position

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
			lda save$xfcb
	inr a
	jnz endsearch1
			lda xdcnt+1
	cpi 0feh
	cz save$dcnt$pos0
			jmp searchn
		endsearch1:
; CPM3_SD81: [endif] (linea 4365)

			xra a
	sta dirloc ; dirloc = 0
			sta lret ; lret = 0
			; successful search -
			; return with zero flag reset
			mov b,a
	inr b
	ret
		searchmod:
			ani 3fh
	ret ; Mask off high 2 bits
		search$fin:
			; end of directory, or empty name

			call save$dcnt$pos1

			; Set dcnt = 0ffffh
			call set$end$dir ; may be artifical end
		lret$eq$ff:
			; unsuccessful search -
			; return with zero flag set
			; lret,low(aret) = 0ffh
			mvi a,255
	mov b,a
	inr b
	jmp sta$ret

		searchnm: ; search no match routine
			mov a,b
	ora a
	jnz searchn ; fcb(0)?
			mov a,m
	ora a
	jnz searchn ; dir fcb(0)=0?
			lda search$user0
	ora a
	jz searchn
			sta user0$pass

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 4408)

			jmp searchok

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 4436)

save$dcnt$pos2:
	; Save directory position of matching fcb
	; under user 0 with matching extent # & modnum = 0
	; a = 0 on entry
	ora b
	pop b
	lxi b,searchn
	push b
	rnz
	inx h
	inx h
	mov a,m
	ora a
	rnz
	; Call if user0pass = 0ffh &
	;	  dir fcb(extnum) = fcb(extnum)
	;	  dir fcb(modnum) = 0
save$dcnt$pos0:
	call save$dcnt$pos ; Return to searchn
save$dcnt$pos1:
	; Save directory position of first empty fcb
	; or the end of the directory

	push h
	lhld xdcnt
	inr h
	jnz save$dcnt$pos$ret ; Return if h ~= 0ffh


save$dcnt$pos:
	lhld dcnt
	shld xdcnt

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 4474)

save$dcnt$pos$ret:
	pop h
	ret

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

init$xfcb$search:
	mvi a,0ffh
init$xfcb$search1:
	sta find$xfcb
	mvi a,0feh
	sta xdcnt+1
	ret

does$xfcb$exist:
	lda xdcnt+1
	cpi 0feh
	rz
	call set$dcnt$dblk
	xra a
	call init$xfcb$search1
	lhld searcha
	mov a,m
	ori 10h
	mov m,a
	mvi c,extnum
	call searchi1
	jmp searchn

xdcnt$eq$dcnt:
	lhld dcnt
	shld xdcnt
	ret

restore$dir$fcb:
	call set$dcnt$dblk
	mvi c,namlen
	call searchi
	jmp searchn
; CPM3_SD81: [endif] (linea 4515)

delete:
	; Delete the currently addressed file
	call get$atts

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	sta attributes
	; Make search return matching fcbs and xfcbs
deletex:
	mvi a,0feh
	call init$xfcb$search1
; CPM3_SD81: [else] (linea 4527)
; CPM3_SD81: [endif] (linea 4532)

; Delete pass 1 - check r/o attributes and xfcb passwords

	call search$extnum
	rz

    delete00:
	    jz delete1

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	    ; Is addressed dir fcb an xfcb?
	    call getdptra
	mov a,m
	ani 10h
	jnz delete01 ; yes

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 4551)

	    ; Check r/o attribute if this is not an
	    ; xfcb only delete operation.
	    lda attributes
	ral
	cnc check$rodir
; CPM3_SD81: [else] (linea 4558)
; CPM3_SD81: [endif] (linea 4560)

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	    ; Are xfcb passwords enabled?
	    call get$dir$mode
	ral
	jc delete02 ; no
; CPM3_SD81: [endif] (linea 4567)

	    ; Is this a wild card delete operation?
	    lhld info
	call chk$wild
	jz delete02 ; yes
	    ; Not wild & passwords inactive
	    ; Skip to pass 2
	    jmp delete11

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

    delete01:
	    ; Check xfcb password if passwords enabled
	    call get$dir$mode
	ral
	jnc delete02
	    call chk$xfcb$password
	jz delete02
	    call chk$pw$error
	jmp deletex
; CPM3_SD81: [endif] (linea 4588)

    delete02:
	    call searchn
	jmp delete00

; Delete pass 2 - delete all matching fcbs and/or xfcbs.

delete1:
	call search$extnum

    delete10:
	    jz copy$dir$loc
    delete11:
	    call getdptra

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	    ; Is addressed dir fcb an xfcb?
	    mov a,m
	ani 10h
	jnz delete12 ; yes
; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 4613)
	    ; Is this delete operation xfcb only?
	    lda attributes
	ani 80h
	jnz delete13 ; yes
; CPM3_SD81: [endif] (linea 4618)

    delete12:
	    ; Delete dir fcb or xfcb
	    ; if fcb free all alocated blocks.

	    mvi m,empty

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

    delete13:
	    push a ; Z flag set => free FCB blocks
	    ; Zero password mode byte in sfcb if sfcb exists
	    ; Does sfcb exist?
	    call get$dtba$8
	ora a
	jnz $+4 ; no
	    ; Zero mode byte
	    mov m,a
; CPM3_SD81: [endif] (linea 4637)

	    call wrdir
	mvi c,0

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	    pop a
	cz scandm$ab
; CPM3_SD81: [else] (linea 4645)
; CPM3_SD81: [endif] (linea 4647)

	    call fix$hash
	    call searchn
	jmp delete10

get$block:
	; Given allocation vector position bc, find the zero bit
	; closest to this position by searching left and right.
	; if found, set the bit to one and return the bit position
	; in hl.  if not found (i.e., we pass 0 on the left, or
	; maxall on the right), return 0000 in hl
	mov d,b
	mov e,c ; copy of starting position to de
	righttst:
		lhld maxall ; value of maximum allocation#
		mov a,e
	sub l
	mov a,d
	sbb h ; right=maxall?
		jnc retblock0 ; return block 0000 if so
		inx d
	push b
	push d ; left, right pushed
		mov b,d
	mov c,e ; ready right for call
		call getallocbit
		rar
	jnc retblock ; Return block number if zero
		pop d
	pop b ; Restore left and right pointers
	lefttst:
		mov a,c
	ora b
	jz righttst ; Skip if left=0000
		; left not at position zero, bit zero?
		dcx b
	push d
	push b ; left,right pushed
		call getallocbit
		rar
	jnc retblock ; return block number if zero
		; bit is one, so try the right
		pop b
	pop d ; left, right restored
		jmp righttst
	retblock:
		ral
	inr a ; bit back into position and set to 1
		; d contains the number of shifts required to reposition
		call rotr ; move bit back to position and store
		pop h
	pop d ; hl returned value, de discarded
		ret
	retblock0:
		; cannot find an available bit, return 0000
		mov a,c
		ora b
	jnz lefttst ; also at beginning
		lxi h,0000h
	ret

copy$dir:
	; Copy fcb information starting at c for e bytes
	; into the currently addressed directory entry
	mvi d,80h
copy$dir0:
	call copy$dir2
	inr c
copy$dir1:
	dcr c
	jz seek$copy
	mov a,m
	ana b
	push b
	mov b,a
	ldax d
	ani 7fh
	ora b
	mov m,a
	pop b
	inx h
	inx d
	jmp copy$dir1
copy$dir2:
	push d ; Save length for later
	mvi b,0 ; double index to bc
	lhld info ; hl = source for data
	dad b
	inx h
	mov a,m
	sui '$'
	cz set$submit$flag
	dcx h
	xchg ; de=.fcb(c), source for copy
	call getdptra ; hl=.buff(dptr), destination
	pop b ; de=source, hl=dest, c=length
	ret

set$submit$flag:
	lxi d,ccp$flgs
	ldax d
	ori 1
	stax d
	ret

check$wild:
	; Check for ? in file name or type
	lhld info
check$wild0:	; entry point used by rename
	call chk$wild
	rnz
	mvi a,9
	jmp set$aret

chk$wild:
	mvi c,11
chk$wild1:
	inx h
	mvi a,3fh
	sub m
	ani 7fh
	rz
	dcr c
	jnz chk$wild1
	ora a
	ret

copy$user$no:
	lhld info
	mov a,m
	lxi b,dskmap
	dad b
	mov m,a
	ret

rename:
	; Rename the file described by the first half of
	; the currently addressed file control block. The
	; new name is contained in the last half of the
	; currently addressed file control block.  The file
	; name and type are changed, but the reel number
	; is ignored.  The user number is identical.

	; Verify that the new file name does not exist.
	; Also verify that no wild chars exist in
	; either filename.

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 4798)

	; Verify that no wild chars exist in 1st filename.
	call check$wild

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	; Check password of file to be renamed.
	call chk$password
	cnz chk$pw$error
	; Setup search to scan for xfcbs.
	call init$xfcb$search
; CPM3_SD81: [endif] (linea 4809)

	; Copy user number to 2nd filename
	call copy$user$no
	shld searcha

	; Verify no wild chars exist in 2nd filename
	call check$wild0

	; Verify new filename does not already exist
	mvi c,extnum
	lhld searcha
	call searchi1
	call search1
	jnz file$exists ; New filename exists

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	; If an xfcb exists for the new filename, delete it.
	call does$xfcb$exist
	cnz delete11
; CPM3_SD81: [endif] (linea 4829)

	call copy$user$no

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	call init$xfcb$search
; CPM3_SD81: [endif] (linea 4835)

	; Search up to the extent field
	call search$extnum
	rz
	call check$rodir ; may be r/o file

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 4844)

	; Copy position 0
	rename0:
		; not end of directory, rename next element
		mvi c,dskmap
	mvi e,extnum
	call copy$dir
		; element renamed, move to next

		call fix$hash
		call searchn
		jnz rename0
	rename1:

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		call does$xfcb$exist
	jz copy$dir$loc
		call copy$user$no
	jmp rename0
; CPM3_SD81: [else] (linea 4864)
; CPM3_SD81: [endif] (linea 4866)

indicators:
	; Set file indicators for current fcb
	call get$atts ; Clear f5' through f8'
	sta attributes

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	call chk$password
	cnz chk$pw$error
; CPM3_SD81: [endif] (linea 4876)

	call search$extnum ; through file type
	rz

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 4883)

	indic0:
		; not end of directory, continue to change
		mvi c,0
	mvi e,extnum ; Copy name
		call copy$dir2
	call move
		lda attributes
	ani 40h
	jz indic1

		; If interface att f6' set, dir fcb(s1) = fcb(cr)

		push h
	call getfcba
	mov a,m
		pop h
	inx h
	mov m,a
	indic1:
		call seek$copy
		call searchn
		jz copy$dir$loc
		jmp indic0

open:
	; Search for the directory entry, copy to fcb
;;;	call search$namlen	;[JCE] DRI Patch 13
	call patch$1e3e
open1:
	rz ; Return with lret=255 if end
	; not end of directory, copy fcb information
open$copy:
	call setfwf
	mov e,a
	push h
	dcx h
	dcx h
	mov d,m
	push d ; Save extent# & module# with fcb bd$write flag set
	call getdptra
	xchg ; hl = .buff(dptr)
	lhld info ; hl=.fcb(0)
	mvi c,nxtrec ; length of move operation
	call move ; from .buff(dptr) to .fcb(0)
	; Note that entire fcb is copied, including indicators
	call get$dir$ext
	mov c,a
	; Restore module # and extent #
	pop d
	pop h
	mov m,e
	dcx h
	dcx h
	mov m,d
	; hl = .user extent#, c = dir extent#
	; above move set fcb(reccnt) to dir(reccnt)
	; if fcb ext < dir ext then fcb(reccnt) = fcb(reccnt) | 128
	; if fcb ext = dir ext then fcb(reccnt) = fcb(reccnt)
	; if fcb ext > dir ext then fcb(reccnt) = 0

set$rc: ; hl=.fcb(ext), c=dirext
		mvi b,0
		xchg
	lxi h,(reccnt-extnum)
	dad d
		; Is fcb ext = dirext?
		ldax d
	sub c
	jz set$rc2 ; yes
		; Is fcb ext > dirext?
		mov a,b
	jnc set$rc1 ; yes - fcb(rc) = 0
		; fcb ext  < dirext
		; fcb(rc) = 128 | fcb(rc)
		mvi a,128
	ora m
	set$rc1:
		mov m,a
	ret
	set$rc2:
		; fcb ext = dirext
		mov a,m
	ora a
	rnz ; ret if fcb(rc) ~= 0
	set$rc3:
		mvi m,0 ; required by function 99
		lda dminx
	ora a
	rz ; ret if no blks in fcb
		mvi m,128
	ret ; fcb(rc) = 128

mergezero:
	; hl = .fcb1(i), de = .fcb2(i),
	; if fcb1(i) = 0 then fcb1(i) := fcb2(i)
	mov a,m
	inx h
	ora m
	dcx h
	rnz ; return if = 0000
	ldax d
	mov m,a
	inx d
	inx h ; low byte copied
	ldax d
	mov m,a
	dcx d
	dcx h ; back to input form
	ret

restore$rc:
	; hl = .fcb(extnum)
	; if fcb(rc) > 80h then fcb(rc) = fcb(rc) & 7fh
	push h
	lxi d,(reccnt-extnum)
	dad d
	mov a,m
	cpi 81h
	jc restore$rc1
	ani 7fh
	mov m,a
restore$rc1:
	pop h
	ret

close:
	; Locate the directory element and re-bd$write it
	xra a
	sta lret

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 5017)

	call nowrite
	rnz ; Skip close if r/o disk
	; Check file bd$write flag - 0 indicates written
	call getmodnum ; fcb(modnum) in a
	ani fwfmsk
	rnz ; Return if bit remains set
close1:
	call chk$inv$fcb
	jz mergerr

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 5031)

;;;	call get$dir$ext
	call patch$1dfd		;[JCE] DRI patch 7

	mov c,a
	mov b,m
	push b
	; b = original extent, c = directory extent
	; Set fcb(ex) to directory extent
	mov m,c
	; Recompute fcb(rc)
	call restore$rc
	; Call set$rc if fcb ext > dir ext
	mov a,c
	cmp b
	cc set$rc
	call close$fcb
	; Restore original extent & reset fcb(rc)
	call get$exta
	pop b
	mov c,m
	mov m,b
	jmp set$rc ; Reset fcb(rc)

close$fcb:
	; Locate file
	call search$namlen
	rz ; Return if not found
	; Merge the disk map at info with that at buff(dptr)
	lxi b,dskmap
	call get$fcb$adds
	mvi c,(fcblen-dskmap) ; length of single byte dm
	merge0:
		lda single
	ora a
	jz merged ; Skip to double
		; This is a single byte map
		; if fcb(i) = 0 then fcb(i) = buff(i)
		; if buff(i) = 0 then buff(i) = fcb(i)
		; if fcb(i) <> buff(i) then error
		mov a,m
	ora a
	ldax d
	jnz fcbnzero
			; fcb(i) = 0
			mov m,a ; fcb(i) = buff(i)
		fcbnzero:
		ora a
	jnz buffnzero
			; buff(i) = 0
			mov a,m
	stax d ; buff(i)=fcb(i)
		buffnzero:
		cmp m
	jnz mergerr ; fcb(i) = buff(i)?
		jmp dmset ; if merge ok
	merged:
		; This is a double byte merge operation
		call mergezero ; buff = fcb if buff 0000
		xchg
	call mergezero
	xchg ; fcb = buff if fcb 0000
		; They should be identical at this point
		ldax d
	cmp m
	jnz mergerr ; low same?
		inx d
	inx h ; to high byte
		ldax d
	cmp m
	jnz mergerr ; high same?
		; merge operation ok for this pair
		dcr c ; extra count for double byte
	dmset:
		inx d
	inx h ; to next byte position
		dcr c
	jnz merge0 ; for more
		; end of disk map merge, check record count
		; de = .buff(dptr)+32, hl = .fcb(32)

		xchg
	lxi b,-(fcblen-extnum)
	dad b
	push h
		call get$dir$ext
	pop d

		; hl = .fcb(extnum), de = .buff(dptr+extnum)

		call compare$extents

		; b=1 -> fcb(ext) ~= dir ext = buff(ext)
		; b=2 -> fcb(ext) = dir ext ~= buff(ext)
		; b=3 -> fcb(ext) = dir ext = buff(ext)

		; fcb(ext), buff(ext) = dir ext
		mov m,a
	stax d
	push b

		lxi b,(reccnt-extnum)
	dad b
	xchg
	dad b
		pop b

		; hl = .buff(rc) , de = .fcb(rc)

		dcr b
	jz mrg$rc1 ; fcb(rc) = buff(rc)

		dcr b
	jz mrg$rc2 ; buff(rc) = fcb(rc)

		ldax d
	cmp m
	jc mrg$rc1 ; Take larger rc
		ora a
	jnz mrg$rc2
		call set$rc3

       mrg$rc1: xchg

       mrg$rc2: ldax d
	mov m,a

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 5163)

		; Set t3' off indicating file update
		call getdptra
	lxi d,11
	dad d
		mov a,m
	ani 7fh
	mov m,a
		call setfwf
		mvi c,1
	call scandm$b ; Set 2nd ALV vector
		jmp seek$copy ; OK to "wrdir" here - 1.4 compat
		; ret
	mergerr:
		; elements did not merge correctly
		call make$fcb$inv
		jmp lret$eq$ff

compare$extents:
	mvi b,1
	cmp m
	rnz
	inr b
	xchg
	cmp m
	xchg
	rnz
	inr b
	ret

set$xdcnt:
	lxi h,0ffffh
	shld xdcnt
	ret

set$dcnt$dblk:
	lhld xdcnt
set$dcnt$dblk1:
	mvi a,11111100b
	ana l
	mov l,a
	dcx h
	shld dcnt

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 5211)

	ret

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 5222)

make:
	; Create a new file by creating a directory entry
	; then opening the file

;;;	lxi h,xdcnt	;[JCE] DRI Patch 13
	call patch$1e31

	call test$ffff
	cnz set$dcnt$dblk

	lhld info
	push h ; Save fcb address, Look for E5
	lxi h,efcb
	shld info ; info = .empty
	mvi c,1

	call searchi
	call searchn

	; zero flag set if no space
	pop h ; Recall info address
	shld info ; in case we return here
	rz ; Return with error condition 255 if not found

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	; Return early if making an xfcb
	lda make$xfcb
	ora a
	rnz
; CPM3_SD81: [endif] (linea 5253)

	; Clear the remainder of the fcb
	; Clear s1 byte
	lxi d,13
	dad d
	mov m,d
	inx h
	; Clear and save file bd$write flag of modnum
	mov a,m
	push a
	push h
	ani 3fh
	mov m,a
	inx h
	mvi a,1
	mvi c,fcblen-namlen ; number of bytes to fill
	make0:
		mov m,d
	inx h
	dcr c
	jnz make0
		dcr a
	mov c,d
	cz get$dtba
		ora a
	mvi c,10
	jz make0
	call setcdr ; may have extended the directory
	; Now copy entry to the directory
	mvi c,0
	lxi d,fcblen
	call copy$dir0
	; and restore the file bd$write flag
	pop h
	pop a
	mov m,a
	; and set the fcb bd$write flag to "1"
	call fix$hash
	jmp setfwf

open$reel:
	; Close the current extent, and open the next one
	; if possible.	rmf is bd$true if in bd$read mode

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	call reset$copy$cr$only
; CPM3_SD81: [endif] (linea 5300)

	call getexta
	mov a,m
	mov c,a
	inr c
	call compext
	jz open$reel3
	push h
	push b
	call close
	pop b
	pop h
	lda lret
	inr a
	rz
	mvi a,maxext
	ana c
	mov m,a ; Incr extent field
	; Advance to module & save
	inx h
	inx h
	mov a,m
	sta save$mod
	jnz open$reel0 ; Jump if in same module

	open$mod:
		; Extent number overflow, go to next module
		inr m ; fcb(modnum)=++1
		; Module number incremented, check for overflow

		mov a,m
	ani 3fh ; Mask high order bits

		jz open$r$err ; cannot overflow to zero

		; otherwise, ok to continue with new module
	open$reel0:
		call set$xdcnt ; Reset xdcnt for make

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 5342)

;;;		call search$namlen	;[JCE] DRI Patch 13 
		call patch$1e3e		;Next extent found?

		jnz open$reel1
			; end of file encountered
			lda rmf
	inr a ; 0ffh becomes 00 if bd$read
			jz open$r$err ; sets lret = 1
			; Try to extend the current file
			call make
			; cannot be end of directory
			jz open$r$err ; with lret = 1

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 5360)

			jmp open$reel2
		open$reel1:
			; not end of file, open
			call open$copy

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 5369)

		open$reel2:

; CPM3_SD81: [if not MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
			call set$lsn
; CPM3_SD81: [endif] (linea 5375)

			call getfcb ; Set parameters
			xra a
	sta vrecord
	jmp sta$ret ; lret = 0
			; ret ; with lret = 0
	open$r$err:
		; Restore module and extent
		call getmodnum
	lda save$mod
	mov m,a
		dcx h
	dcx h
	mov a,m
	dcr a
	ani 1fh
		mov m,a
	jmp setlret1 ; lret = 1

	open$reel3:
		inr m ; fcb(ex) = fcb(ex) + 1
		call get$dir$ext
	mov c,a
		; Is new extent beyond dir$ext?
		cmp m
	jnc open$reel4 ; no
		dcr m ; fcb(ex) = fcb(ex) - 1
		; Is this a bd$read fx?
		lda rmf
	inr a
	jz set$lret1 ; yes - Don't advance ext
		inr m ; fcb(ex) = fcb(ex) + 1
	open$reel4:
		call restore$rc
		call set$rc
	jmp open$reel2

seqdiskread:
diskread:	; (may enter from seqdiskread)
	call tst$inv$fcb ; Check for valid fcb
	mvi a,bd$true
	sta rmf ; bd$read mode flag = bd$true (open$reel)

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 5421)

	; Read the next record from the current fcb
	call getfcb ; sets parameters for the bd$read
diskread0:
	lda vrecord
	lxi h,rcount
	cmp m ; vrecord-rcount
	; Skip if rcount > vrecord
	jc recordok

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 5436)

		; not enough records in the extent
		; record count must be 128 to continue
		cpi 128 ; vrecord = 128?
		jnz setlret1 ; Skip if vrecord<>128
		call open$reel ; Go to next extent if so
		; Check for open ok
		lda lret
	ora a
	jnz setlret1 ; Stop at eof
	recordok:
		; Arrive with fcb addressing a record to bd$read

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		call set$copy$cr$only
; CPM3_SD81: [endif] (linea 5452)

		call index ; Z flag set if arecord = 0

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 5460)

		jz setlret1 ; Reading unwritten data
	recordok1:
		; Record has been allocated, bd$read it
		call atran ; arecord now a disk address
		call check$nprs
		jc setfcb
		jnz read$deblock

		call setdata
		call seek ; to proper track,sector

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		mvi a,1
	call setbnkf
; CPM3_SD81: [endif] (linea 5476)

		call rdbuff ; to dma address
		jmp setfcb ; Replace parameter

read$deblock:
	lxi h,0
	shld last$block
	mvi a,1
	call deblock$dta
	jmp setfcb

check$nprs:
	;
	; on exit,  c flg	   -> no i/o operation
	;	    z flg & ~c flg -> direct(physical) i/o operation
	;	   ~z flg & ~c flg -> indirect(deblock) i/o operation
	;
	;	   Dir$cnt contains the number of 128 byte records
	;	   to transfer directly.  This routine sets dir$cnt
	;	   when initiating a sequence of direct physical
	;	   i/o operations.  Dir$cnt is decremented each
	;	   time check$nprs is called during such a sequence.
	;
	; Is direct transfer operation in progress?
	lda blk$off
	mov b,a
	lda phy$msk
	mov c,a
	ana b
	push a
	lda dir$cnt
	cpi 2
	jc check$npr1 ; no
	; yes - Decrement direct record count
	dcr a
	sta dir$cnt
	; Are we at a new physical record?
	pop a
	stc
	rnz ; no - ret with c flg set
	; Perform physical i/o operation
	xra a
	ret ; Return with z flag set and c flag reset
check$npr1:
	; Are we in mid-physical record?
	pop a
	jz check$npr11 ; no
check$npr1a:
	; Is phymsk = 0?
	mov a,c
	ora a
	rz ; yes - Don't deblock
check$npr1b:
	; Deblocking required
	ori 1
	ret ; ret with z flg reset and c flg reset
check$npr11:
	mov a,c
	cma
	mov d,a ; d = ~phy$msk
	lxi h,vrecord
	; Is mult$num < 2?
	lda mult$num
	cpi 2
	jc check$npr1a ; yes
	add m
	cpi 80h
	jc check$npr2
	mvi a,80h
check$npr2: ; a = min(vrecord + mult$num),80h) = x
	push b ; Save low(arecord) & blkmsk, phymsk
	mov b,m
	mvi m,7fh ; vrecord = 7f
	push b ; Save vrecord
	push h ; Save .vrecord
	push a ; Save x
	lda blkmsk
	mov e,a
	inr e
	cma
	ana b
	mov b,a
	; b = vrecord & ~blkmsk
	; e = blkmsk + 1
	pop h ; h = x
	; Is this a bd$read function?
	lda rmf
	ora a
	jz check$npr21 ; no
	; Is rcount & ~phymsk < x?
	lda rcount
	ana d
	cmp h
	jc check$npr23 ; yes
check$npr21:
	mov a,h ; a = x
check$npr23:
	sub b ; a = a - vrecord & ~blkmsk
	mov c,a ; c = max # of records from beginning of curr blk
	; Is c < blkmsk+1?
	cmp e
	jc check$npr8 ; yes

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	push b ; c = max # of records
	; Compute maximum disk map position
	call dm$position
	mov b,a ; b = index of last block in extent
	; Does the last block # = the current block #?
	lda dminx
	cmp b
	mov e,a
	jz check$npr5 ; yes
	; Compute # of blocks in sequence
	mov c,a
	push b
	mvi b,0
	call get$dm ; hl = current block #
check$npr4:
	; Get next block #
	push h
	inx b
	call get$dm
	pop d
	inx d
	; Does next block # = previous block # + 1?
	mov a,d
	sub h
	mov d,a
	mov a,e
	sub l
	ora d
	jz check$npr4 ; yes
	; Is next block # = 0?
	mov a,h
	ora l
	jnz check$npr45 ; no
	; Is this a bd$read function?
	lda rmf
	ora a
	jnz check$npr45 ; no
	; Is next block # > maxall?
	lhld maxall
	mov a,l
	sub e
	mov a,h
	sbb d
	jc check$npr45 ; yes
	; Is next block # allocated?
	push b
	push d
	mov b,d
	mov c,e
	call getallocbit
	pop h
	pop b
	rar
	jnc check$npr4 ; no - it will be later
check$npr45:
	dcr c
	pop d
	; Is max dm position less than c?
	mov a,d
	cmp c
	jc check$npr5 ; yes
	mov a,c ; no
check$npr5: ; a = index of last block
	sub e
	mov b,a
	inr b ; b = # of consecutive blks
	lda blkmsk
	inr a
	mov c,a
check$npr6:
	dcr b
	jz check$npr7
	add c
	jmp check$npr6
check$npr7:
	pop b
	mov b,c ; b = max # of records
	mov c,a ; c = (# of consecutive blks)*(blkmsk+1)
	lda rmf
	ora a
	jz check$npr8
	mov a,b
	cmp c
	jc check$npr9
; CPM3_SD81: [else] (linea 5665)
; CPM3_SD81: [endif] (linea 5667)

check$npr8:
	mov a,c
check$npr9:
	; Restore vrecord
	pop h
	pop b
	mov m,b
	pop b
	; a = max # of consecutive records including current blk
	; b = low(arecord) & blkmsk
	; c = phymsk
	; Is mult$num > a - b
	lxi h,mult$num
	mov d,m
	sub b
	cmp d
	jnc check$npr10
	mov d,a ; yes - use smaller value to compute dir$cnt
check$npr10:
	; Does this operation involve at least 1 physical record?
	mov a,c
	cma
	ana d
	sta dir$cnt
	jz check$npr1b ; Deblocking required
	; Flush any pending buffers before doing multiple reads
	push a
	lda rmf
	ora a
	jz check$npr10a
	call flushx
	call setdata
check$npr10a:
	pop a
	mov h,a ; Save # of 128 byte records
	; Does this operation involve more than 1 physical record?
	; Register h contains number of 128 byte records
	call shr$physhf
	mov a,h
	cpi 1
	mov c,a
	cnz mult$iof ; yes - Make bios call
	xra a
	ret ; Return with z flg set

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 5743)

reset$fwf:
	call getmodnum ; hl=.fcb(modnum), a=fcb(modnum)
	; Reset the file bd$write flag to mark as written fcb
	ani (not fwfmsk) and 0ffh ; bit reset
	mov m,a ; fcb(modnum) = fcb(modnum) and 7fh
	ret

set$filewf:
	call getmodnum
	ani 01000000b
	push a
	mov a,m
	ori 01000000b
	mov m,a
	pop a
	ret

seqdiskwrite:
diskwrite:	; (may enter here from seqdiskwrite above)
	mvi a,bd$false
	sta rmf ; bd$read mode flag
	; Write record to currently selected file

	call check$write ; in case bd$write protected

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	lda xfcb$read$only
	ora a
	mvi a,3
	jnz set$aret
; CPM3_SD81: [endif] (linea 5775)

	lda high$ext

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 5781)
	ora a
; CPM3_SD81: [endif] (linea 5783)

	; Z flag reset if r/o mode
	mvi a,3
	jnz set$aret

	lhld info ; hl = .fcb(0)
	call check$rofile ; may be a bd$read-only file

	call tst$inv$fcb ; Test for invalid fcb

	call update$stamp

	call getfcb ; to set local parameters
	lda vrecord
	cpi lstrec+1 ; vrecord-128
	jc diskwrite0
	call open$reel ; vrecord = 128, try to open next extent
	lda lret
	ora a
	rnz ; no available fcb
disk$write0:

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 5811)

	; Can bd$write the next record, so continue
	call index ; Z flag set if arecord = 0
	jz diskwrite2
	; Was the last bd$write operation for the same block & drive?
	lxi h,adrive
	lxi d,last$drive
	mvi c,3
	call compare
	jz diskwrite15 ; yes
	; no - force preread in blocking/deblocking
	mvi a,0ffh
	sta last$off
diskwrite15:

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 5845)

	mvi c,0 ; Marked as normal bd$write operation for wrbuff
	jmp diskwr1
diskwrite2:

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 5854)

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		call reset$copy$cr$only
; CPM3_SD81: [endif] (linea 5858)

		; not allocated
		; The argument to getblock is the starting
		; position for the disk search, and should be
		; the last allocated block for this file, or
		; the value 0 if no space has been allocated
		call dm$position
		sta dminx ; Save for later
		lxi b,0000h ; May use block zero
		ora a
	jz nopblock ; Skip if no previous block
			; Previous block exists at a
			mov c,a
	dcx b ; Previous block # in bc
			call getdm ; Previous block # to hl
			mov b,h
	mov c,l ; bc=prev block#
		nopblock:
			; bc = 0000, or previous block #
			call get$block ; block # to hl
		; Arrive here with block# or zero
		mov a,l
	ora h
	jnz blockok
			; Cannot find a block to allocate
			mvi a,2
	jmp sta$ret ; lret=2
		blockok:

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 5890)

		; allocated block number is in hl
		shld arecord
	shld last$block
	xra a
	sta last$off
		lda adrive
	sta lastdrive
		xchg ; block number to de
		lhld info
	lxi b,dskmap
	dad b ; hl=.fcb(dskmap)
		lda single
	ora a ; Set flags for single byte dm
		lda dminx ; Recall dm index
		jz allocwd ; Skip if allocating word
			; Allocating a byte value
			call addh
	mov m,e ; single byte alloc
			jmp diskwru ; to continue
		allocwd:
		; Allocate a word value
			mov c,a
	mvi b,0 ; double(dminx)
			dad b
	dad b ; hl=.fcb(dminx*2)
			mov m,e
	inx h
	mov m,d ; double wd
		diskwru:
		; disk bd$write to previously unallocated block
		mvi c,2 ; marked as unallocated bd$write
	diskwr1:
	; Continue the bd$write operation of no allocation error
	; c = 0 if normal bd$write, 2 if to prev unalloc block
	push b ; Save bd$write flag
	call atran ; arecord set
diskwr10:
		lda fx
	cpi 40
	jnz diskwr11 ; fx ~= wrt rndm zero fill
		mov a,c
	dcr a
	dcr a
	jnz diskwr11 ; old allocation

		; bd$write random zero fill + new block

		pop b
	push a ; zero bd$write flag
		lhld arecord
	push h
		lxi h,phymsk
	mov e,m
	inr e
	mov d,a
	push d
		lhld dirbcba

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		mov e,m
	inx h
	mov d,m
	xchg
fill00:
		push h
	call get$next$bcba
	pop d
	jnz fill00
		xchg
; CPM3_SD81: [endif] (linea 5961)

		; Force prereads in blocking/deblocking
		; Discard BCB
		dcr a
	sta last$off
	mov m,a
		call setdir1 ; Set dma to BCB buffer
		; Zero out BCB buffer
		pop d
	push d
	xra a
	fill0:
		mov m,a
	inx h
	inr d
	jp fill0
		mov d,a
	dcr e
	jnz fill0
		; Write 1st physical record of block
		lhld arecord1
	mvi c,2
	fill1:
		shld arecord
	push b
	call discard$data$bcb
		call seek

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		xra a
	call setbnkf
; CPM3_SD81: [endif] (linea 5993)

		pop b
	call wrbuff
		lhld arecord
	pop d
	push d
		; Continue writing until blkmsk & arecord = 0
		dad d
	lda blkmsk
	ana l
	mvi c,0
	jnz fill1
		; Restore arecord
		pop h
	pop h
	shld arecord

		call setdata ; Restore dma
	diskwr11:

	pop d
	lda vrecord
	mov d,a ; Load and save vrecord
	push d
	call check$nprs

	jc dont$write
	jz bd$write

	mvi a,2 ; deblock bd$write code
	call deblock$dta
	jmp dont$write
bd$write:
	call setdata
	call seek

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	mvi a,1
	call setbnkf
; CPM3_SD81: [endif] (linea 6033)

	; Discard matching BCB if bd$write is direct
	call discard$data$bcb

	; Set bd$write flag to zero if arecord & blkmsk ~= 0

	pop b
	push b
	lda arecord
	lxi h,blkmsk
	ana m
	jz write0
	mvi c,0
write0:
	call wrbuff

dont$write:
	pop b ; c = 2 if a new block was allocated, 0 if not
	; Increment record count if rcount<=vrecord
	mov a,b
	lxi h,rcount
	cmp m ; vrecord-rcount
	jc diskwr2
		; rcount <= vrecord
		mov m,a
	inr m ; rcount = vrecord+1

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 6079)

		mvi c,2 ; Mark as record count incremented
	diskwr2:
	; a has vrecord, c=2 if new block or new record#
	dcr c
	dcr c
	jnz noupdate
		call reset$fwf

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 6097)

noupdate:
	; Set file bd$write flag if reset
	call set$filewf

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	jnz disk$write3
	; Reset fcb file bd$write flag to ensure t3' gets
	; reset by the close function
	call reset$fwf
	call reset$copy$cr$only
	jmp setfcb
disk$write3:
	call set$copy$cr$only
; CPM3_SD81: [else] (linea 6112)
; CPM3_SD81: [endif] (linea 6114)
	jmp setfcb ; Replace parameters
	; ret

rseek:
	; Random access seek operation, c=0ffh if bd$read mode
	; fcb is assumed to address an active file control block
	; (1st block of FCB = 0ffffh if previous bad seek)
	push b ; Save r/w flag
	lhld info
	xchg ; de will hold base of fcb
		lxi h,ranrec
	dad d ; hl=.fcb(ranrec)
		mov a,m
	ani 7fh
	push psw ; record number
		mov a,m
	ral ; cy=lsb of extent#
		inx h
	mov a,m
	ral
	ani 11111b ; a=ext#
		mov c,a ; c holds extent number, record stacked

		mov a,m
	ani 11110000b
	inx h
	ora m
		rrc
	rrc
	rrc
	rrc
	mov b,a
		; b holds module #

		; Check high byte of ran rec <= 3
		mov a,m
		ani 11111100b
	pop h
	mvi l,6
	mov a,h

		; Produce error 6, seek past physical eod
		jnz seekerr

		; otherwise, high byte = 0, a = sought record
		lxi h,nxtrec
	dad d ; hl = .fcb(nxtrec)
		mov m,a ; sought rec# stored away

	; Arrive here with b=mod#, c=ext#, de=.fcb, rec stored
	; the r/w flag is still stacked.  compare fcb values

		lda fx
	cpi 99
	jz rseek3
		; Check module # first
		push d
	call chk$inv$fcb
	pop d
	jz ranclose
		lxi h,modnum
	dad d
	mov a,b ; b=seek mod#
		sub m
	ani 3fh
	jnz ranclose ; same?
		; Module matches, check extent
		lxi h,extnum
	dad d
		mov a,m
	cmp c
	jz seekok2 ; extents equal
		call compext
	jnz ranclose
		; Extent is in same directory fcb
		push b
	call get$dir$ext
	pop b
		cmp c
	jnc rseek2 ; jmp if dir$ext > ext
		pop d
	push d
	inr e
	jnz rseek2 ; jmp if bd$write fx
		inr e
	pop d
	jmp set$lret1 ; error - reading unwritten data
	rseek2:
		mov m,c ; fcb(ext) = c
		mov c,a ; c = dir$ext
		; hl=.fcb(ext),c=dir ext
		call restore$rc
		call set$rc
		jmp seekok1
	ranclose:
		push b
	push d ; Save seek mod#,ext#, .fcb
		call close ; Current extent closed
		pop d
	pop b ; Recall parameters and fill
		mvi l,3 ; Cannot close error #3
		lda lret
	inr a
	jz seekerr
	rseek3:
		call set$xdcnt ; Reset xdcnt for make

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 6224)

		lxi h,extnum
	dad d
	push h
		mov d,m
	mov m,c ; fcb(extnum)=ext#
		inx h
	inx h
	mov a,m
	mov e,a
	push d
		ani 040h
	ora b
	mov m,a
		; fcb(modnum)=mod#
		call open ; Is the file present?
		lda lret
	inr a
	jnz seekok ; Open successful?
		; Cannot open the file, bd$read mode?
		pop d
	pop h
	pop b ; r/w flag to c (=0ffh if bd$read)
		push b
	push h
	push d ; Restore stack
		mvi l,4 ; Seek to unwritten extent #4
		inr c ; becomes 00 if bd$read operation
		jz badseek ; Skip to error if bd$read operation
		; Write operation, make new extent
		call make
		mvi l,5 ; cannot create new extent #5
		jz badseek ; no dir space

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 6261)

		; file make operation successful
	seekok:
		pop b
	pop b ; Discard top 2 stacked items

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 6270)
		call set$lsn
; CPM3_SD81: [endif] (linea 6272)

	seekok1:

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		call reset$copy$cr$only
; CPM3_SD81: [endif] (linea 6278)

	seekok2:
		pop b ; Discard r/w flag or .fcb(ext)
		xra a
	jmp sta$ret ; with zero set
	badseek:
		; Restore fcb(ext) & fcb(mod)
		pop d
	xthl ; Save error flag
		mov m,d
	inx h
	inx h
	mov m,e
		pop h ; Restore error flag
	seekerr:

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		call reset$copy$cr$only ; Z flag set
		inr a ; Reset Z flag
; CPM3_SD81: [endif] (linea 6298)

		pop b ; Discard r/w flag
		mov a,l
	jmp sta$ret ; lret=#, nonzero

randiskread:
	; Random disk bd$read operation
	mvi c,bd$true ; marked as bd$read operation
	call rseek
	cz diskread ; if seek successful
	ret

randiskwrite:
	; Random disk bd$write operation
	mvi c,bd$false ; marked as bd$write operation
	call rseek
	cz diskwrite ; if seek successful
	ret

compute$rr:
	; Compute random record position for getfilesize/setrandom
	xchg
	dad d
	; de=.buf(dptr) or .fcb(0), hl = .f(nxtrec/reccnt)
	mov c,m
	mvi b,0 ; bc = 0000 0000 ?rrr rrrr
	lxi h,extnum
	dad d
	mov a,m
	rrc
	ani 80h ; a=e000 0000
	add c
	mov c,a
	mvi a,0
	adc b
	mov b,a
	; bc = 0000 000? errrr rrrr
	mov a,m
	rrc
	ani 0fh
	add b
	mov b,a
	; bc = 000? eeee errrr rrrr
	lxi h,modnum
	dad d
	mov a,m ; a=xxmm mmmm
	add a
	add a
	add a
	add a ; cy=m a=mmmm 0000

	ora a
	add b
	mov b,a
	push psw ; Save carry
	mov a,m
	rar
	rar
	rar
	rar
	ani 00000011b ; a=0000 00mm
	mov l,a
	pop psw
	mvi a,0
	adc l ; Add carry
	ret

compare$rr:
	mov e,a ; Save cy
	mov a,c
	sub m
	mov d,a
	inx h ; lst byte
	mov a,b
	sbb m
	inx h ; middle byte
	push a
	ora d
	mov d,a
	pop a
	mov a,e
	sbb m ; carry if .fcb(ranrec) > directory
	ret

set$rr:
	mov m,e
	dcx h
	mov m,b
	dcx h
	mov m,c
	ret

getfilesize:
	; Compute logical file size for current fcb
	; Zero the receiving ranrec field
	call get$rra
	push h ; Save position
	mov m,d
	inx h
	mov m,d
	inx h
	mov m,d ; =00 00 00
	call search$extnum
	getsize:
		jz setsize
		; current fcb addressed by dptr
		call getdptra
	lxi d,reccnt ; ready for compute size
		call compute$rr
		; a=0000 00mm bc = mmmm eeee errr rrrr
		; Compare with memory, larger?
		pop h
	push h ; Recall, replace .fcb(ranrec)
		call compare$rr
	cnc set$rr
		call searchn
		mvi a,0
	sta aret
		jmp getsize
	setsize:

	pop h ; Discard .fcb(ranrec)
	ret

setrandom:
	; Set random record from the current file control block
	xchg
	lxi d,nxtrec ; Ready params for computesize
	call compute$rr ; de=info, a=0000 00mm, bc=mmmm eeee errr rrrr
	lxi h,ranrec
	dad d ; hl = .fcb(ranrec)
	mov m,c
	inx h
	mov m,b
	inx h
	mov m,a ; to ranrec
	ret

disk$select:
	; Select disk info for subsequent input or output ops
	sta adrive
disk$select1: ; called by deblock
	mov m,a ; curdsk = bd$seldsk or adrive
	mov d,a ; Save bd$seldsk in register D for selectdisk call
	lhld dlog
	call test$vector ; test$vector does not modify DE
	mov e,a
	push d ; Send to bd$seldsk, save for test below
	call selectdisk
	pop h ; Recall dlog vector
	jnc sel$error ; returns with C flag set if select ok
	; Is the disk logged in?
	dcr l ; reg l = 1 if so
	ret

tmpselect:
	lxi h,bd$seldsk
	mov m,e

curselect:
	lda bd$seldsk
	lxi h,curdsk
	cmp m
	jnz select
	cpi 0ffh
	rnz ; return if bd$seldsk ~= ffh

select:
	call disk$select

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 6478)
	rz ; yes - drive previously logged in
; CPM3_SD81: [endif] (linea 6480)

	call initialize ; Log in the directory

	; Increment login sequence # if odd
	lhld lsn$add
	mov a,m
	ani 1
	push a
	add m
	mov m,a
	pop a
	cnz set$rlog

	call set$dlog

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 6507)

	ret

reselectx:
	xra a
	sta high$ext

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	sta xfcb$read$only
; CPM3_SD81: [endif] (linea 6517)

	jmp reselect1

reselect:
	; Check current fcb to see if reselection necessary
	lxi b,807fh
	lhld info
	lxi d,7
	xchg
	dad d

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	; xfcb$read$only = 80h & fcb(7)
	mov a,m
	ana b
	sta xfcb$read$only
	; fcb(7) = fcb(7) & 7fh
	mov a,m
	ana c
	mov m,a
; CPM3_SD81: [endif] (linea 6538)

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 6557)
	; high$ext = 80h & fcb(8)
	inx h
	mov a,m
	ana b
	sta high$ext
	; fcb(8) = fcb(8) & 7fh
	mov a,m
	ana c
	mov m,a
; CPM3_SD81: [endif] (linea 6567)

	; fcb(ext) = fcb(ext) & 1fh
	call clr$ext
reselect1:

	lxi h,0

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	shld make$xfcb ; make$xfcb,find$xfcb = 0
; CPM3_SD81: [endif] (linea 6577)
	shld xdcnt ; required by directory hashing

	xra a
	sta search$user0
	dcr a
	sta resel ; Mark possible reselect
	lhld info
	mov a,m ; drive select code
	sta fcbdsk ; save drive code
	ani 11111b ; non zero is auto drive select
	dcr a ; Drive code normalized to 0..30, or 255
	sta linfo ; Save drive code
	cpi 0ffh
	jz noselect
		; auto select function, bd$seldsk saved above
		sta bd$seldsk
	noselect:
		call curselect
		; Set user code
		lda usrcode ; 0...15
		lhld info
	mov m,a
	noselect0:
		; Discard directory BCB's if drive is removable
		; and fx = 15,17,19,22,23,30 etc.
		call tst$log$fxs
	cz discard$dir
		; Check for media change on currently slected disk
		call check$media
		; Check for media change on any other disks
		jmp check$all$media

check$media:
	; Check media if DPH media flag set.
	; Is DPH media flag set?
	call test$media$flag
	rz ; no
	; Test for media change by reading directory
	; to current high water mark or until media change
	; is detected.
	; First reset DPH media flag & discard directory BCB's
	mvi m,0
	call discard$dir
	lhld dcnt
	push h
	call bd$home
	call set$end$dir
check$media1:
	mvi c,bd$false
	call r$dir
	lxi h,relog
	mov a,m
	ora a
	jz check$media2
	mvi m,0
	pop h
	lda fx
	cpi 48
	rz
	call drv$relog
	jmp chk$exit$fxs
check$media2:
	call comp$cdr
	jc check$media1
	pop h
	shld dcnt
	ret

check$all$media:
	; This routine checks all logged-in drives for
	; a set DPH media flag and pending buffers.  It reads
	; the directory for these drives to verify that media
	; has not changed.  If media has changed, the drives
	; get reset (but not relogged-in).
	; Is SCB media flag set?
	lxi h,media$flag
	mov a,m
	ora a
	rz ; no
	; Reset SCB media flag
	mvi m,0
	; Test logged-in drives only
	lhld dlog
	mvi a,16
chk$am1:
	dcr a
	dad h
	jnc chk$am2
	; A = drive #
	; Select drive
	push a
	push h
	lxi h,curdsk
	call disk$select
	; Does drive have pending data buffers?
	call test$pending
	cnz check$media ; yes
	pop h
	pop a
chk$am2:
	ora a
	jnz chk$am1
	jmp curselect

test$pending:
	; On return, Z flag reset if buffer pending

	; Does dta$bcba = 0ffffh
	lhld dta$bcba
	mov a,l
	ana h
	inr a
	rz ; yes

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

test$p1:
	; Does bcb addr = 0?
	mov e,m
	inx h
	mov d,m
	mov a,e
	ora d
	rz ; yes - no pending buffers
	lxi h,4
; CPM3_SD81: [else] (linea 6703)
; CPM3_SD81: [endif] (linea 6705)

	; Is buffer pending?
	dad d
	mov a,m
	ora a ; A ~= 0 if so

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	rnz ; yes
	; no - advance to next bcb
	lxi h,13
	dad d
	jmp test$p1
; CPM3_SD81: [else] (linea 6718)
; CPM3_SD81: [endif] (linea 6720)

get$dir$mode:
	lhld drvlbla
	mov a,m

; CPM3_SD81: [if not BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 6728)

	ret

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

chk$password:
	call get$dir$mode
	ani 80h
	rz

chk$pw:		; Check password
	call get$xfcb
	rz ; a = xfcb options
	jmp cmp$pw

chk$pw$error:
	; Disable special searches
	xra a
	sta xdcnt+1
	; pw$fcb = dir$xfcb
	call getdptra
	xchg
	mvi c,12
	lxi h,pw$fcb
	push h
	call move
	ldax d
	inx h
	mov m,a
	pop d
	lhld info
	mov a,m
	stax d
	; push original info and xfcb password mode
	; info = .pw$fcb
	push h
	xchg
	shld info
	; Does fcb(ext = 0, mod = 0) exist?
	call search$namlen
	jz chk$pwe2 ; no
	; Does sfcb exist for fcb ?
	call get$dtba$8
	ora a
	jnz chk$pwe1 ; no
	xchg
	lxi h,pw$mode
	; Is sfcb password mode nonzero?
	mov b,m
	ldax d
	mov m,a
	ora a
	jz chk$pwe2 ; no
	; Do password modes match?
	xra b
	ani 0e0h
	jz chk$pwe1 ; yes
	; no - update xfcb to match sfcb
	call get$xfcb
	jz chk$pwe1 ; no xfcb (error)
	lda pw$mode
	mov m,a
	call nowrite
	cz seek$copy
chk$pwe1:
	pop h
	shld info
	lda fx
	cpi 15
	rz
	cpi 22
	rz

pw$error:	; password error
	mvi a,7
	jmp set$aret

chk$pwe2:
	xra a
	sta pw$mode
	call nowrite
	jnz chk$pwe3
	; Delete xfcb
	call get$xfcb
	push a
	lhld info
	mov a,m
	ori 10h
	mov m,a
	pop a
	cnz delete$10
chk$pwe3:
	; Restore info
	pop h
	shld info
	ret

cmp$pw:		; Compare passwords
	inx h
	mov b,m
	mov a,b
	ora a
	jnz cmp$pw2
	mov d,h
	mov e,l
	inx h
	inx h
	mvi c,9
cmp$pw1:
	inx h
	mov a,m
	dcr c
	rz
	ora a
	jz cmp$pw1
	cpi 20h
	jz cmp$pw1
	xchg
cmp$pw2:
	lxi d,(23-ubytes)
	dad d
	xchg
	lhld xdmaad
	mvi c,8
cmp$pw3:
	ldax d
	xra b
	cmp m
	jnz cmp$pw4
	dcx d
	inx h
	dcr c
	jnz cmp$pw3
	ret
cmp$pw4:
	dcx d
	dcr c
	jnz cmp$pw4
	inx d

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 6877)
	lxi h,df$password
; CPM3_SD81: [endif] (linea 6879)

	mvi c,8
	jmp compare

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 6903)

set$pw:		; Set password in xfcb
	push h ; Save .xfcb(ex)
	lxi b,8 ; b = 0, c = 8
	lxi d,(23-extnum)
	dad d
	xchg
	lhld xdmaad
set$pw0:
	xra a
	push a
set$pw1:
	mov a,m
	stax d
	ora a
	jz set$pw2
	cpi 20h
	jz set$pw2
	inx sp
	inx sp
	push a
set$pw2:
	add b
	mov b,a
	dcx d
	inx h
	dcr c
	jnz set$pw1
	pop a
	ora b
	pop h
	jnz set$pw3
	; is fx = 100 (directory label)?
	lda fx
	cpi 100
	jz set$pw3 ; yes
	mvi m,0 ; zero xfcb(ex) - no password
set$pw3:
	inx d
	mvi c,8
set$pw4:
	ldax d
	xra b
	stax d
	inx d
	dcr c
	jnz set$pw4
	inx h
	ret

get$xfcb:
	lhld info
	mov a,m
	push a
	ori 010h
	mov m,a
	call search$extnum
	mvi a,0
	sta lret
	lhld info
	pop b
	mov m,b
	rz
get$xfcb1:
	call getdptra
	xchg
	lxi h,extnum
	dad d
	mov a,m
	ani 0e0h
	ori 1
	ret

adjust$dmaad:
	push h
	lhld xdmaad
	dad d
	shld xdmaad
	pop h
	ret

init$xfcb:
	call setcdr ; may have extended the directory
	lxi b,1014h ; b=10h, c=20
init$xfcb0:
	; b = fcb(0) logical or mask
	; c = zero count
	push b
	call getdptra
	xchg
	lhld info
	xchg
	; Zero extnum and modnum
	ldax d
	ora b
	mov m,a
	inx d
	inx h
	mvi c,11
	call move
	pop b
	inr c
init$xfcb1:
	dcr c
	rz
	mvi m,0
	inx h
	jmp init$xfcb1

chk$xfcb$password:
	call get$xfcb1
chk$xfcb$password1:
	push h
	call cmp$pw
	pop h
	ret

; CPM3_SD81: [endif] (linea 7021)

stamp1:
	mvi c,0
	jmp stamp3
stamp2:
	mvi c,4
stamp3:
	call get$dtba
	ora a
	rnz
	lxi d,seek$copy
	push d
stamp4:

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 7041)
	lxi d,stamp
; CPM3_SD81: [endif] (linea 7043)

	push h
	push d
	mvi c,0
	call timef ; does not modify hl,de
	mvi c,4
	call compare
	mvi c,4
	pop d
	pop h
	jnz move
	pop h
	ret

stamp5:
	call getdptra
	dad b
	lxi d,func$ret
	push d
	jmp stamp4

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

get$dtba$8:
	mvi c,8
; CPM3_SD81: [endif] (linea 7069)

get$dtba:
	; c = offset of sfcb subfield (0,4,8)
	; Return with a = 0 if sfcb exists

	; Does fcb occupy 4th item of sector?
	lda dcnt
	ani 3
	cpi 3
	rz ; yes
	mov b,a
	lhld buffa
	lxi d,96
	dad d
	; Does sfcb reside in 4th directory item?
	mov a,m
	sui 21h
	rnz ; no
	; hl = hl + 10*lret + 1 + c
	mov a,b
	add a
	mov e,a
	add a
	add a
	add e
	inr a
	add c
	mov e,a
	dad d
	xra a
	ret

qstamp:
	; Is fcb 1st logical fcb for file?
	call qdirfcb1
	rnz ; no
qstamp1:
	; Does directory label specify requested stamp?
	lhld drvlbla
	mov a,c
	ana m
	jnz nowrite ; yes - verify drive r/w
	inr a
	ret ; no - return with Z flag reset

qdirfcb1:
	; Routine to determine if fcb is 1st directory fcb
	; for file
	; Is fcb(ext) & ~extmsk & 00011111b = 0?
	lda extmsk
	ori 11100000b
	cma
	mov b,a
	call getexta
	mov a,m
	ana b
	rnz ; no
	; is fcb(mod) & 0011$1111B = 0?
	inx h
	inx h
	mov a,m
	ani 3fh
	ret ; Z flag set if zero

update$stamp:
	; Is update stamping requested on drive?
	mvi c,00100000b
	call qstamp1
	rnz ; no
	; Has file been written to since it was opened?
	call getmodnum
	ani 40h
	rnz ; yes - update stamp performed
	; Search for 1st dir fcb
	call getexta
	mov b,m
	mvi m,0
	push h
	inx h
	inx h
	mov c,m
	mvi m,0
	push b
	; Search from beginning of directory
	call search$namlen
	; Perform update stamp if dir fcb 1 found
	cnz stamp2
	xra a
	sta lret
	; Restore fcb extent and module fields
	pop b
	pop h
	mov m,b
	inx h
	inx h
	mov m,c
	ret

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 8092)

;
;	individual function handlers
;

func12:
	; Return version number

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 8104)
	lda version
	jmp sta$ret ; lret = dvers (high = 00)
; CPM3_SD81: [endif] (linea 8107)

func13:

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 8130)
	lxi h,0ffffh
	call reset$37x
; CPM3_SD81: [endif] (linea 8133)
	xra a
	sta olddsk ; Note that usrcode remains unchanged

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 8155)
	lxi h,tbuff
	shld dmaad ; dmaad = tbuff
	jmp setdata ; to data dma address
; CPM3_SD81: [endif] (linea 8159)

func14:

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 8183)
	call tmpselect ; bd$seldsk = reg e
	lda bd$seldsk
	sta olddsk
	ret
; CPM3_SD81: [endif] (linea 8188)

func15:
	; Open file
	call clrmodnum ; Clear the module number

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 8214)
	call reselectx
; CPM3_SD81: [endif] (linea 8216)

	call check$wild ; Check for wild chars in fcb

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 8239)

	lda usrcode
	ora a
	jz call$open
	mvi a,0feh
	sta xdcnt+1
	inr a
	sta search$user0

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 8251)

call$open:
	call open
	call openx ; returns if unsuccessful, a = 0
	lxi h,search$user0
	cmp m
	rz
	mov m,a
	lda xdcnt+1
	cpi 0feh
	rz
;
;	file exists under user 0
;

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 8269)

	call set$dcnt$dblk

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 8275)
	mvi a,80h
; CPM3_SD81: [endif] (linea 8277)

	sta high$ext
open$user$zero:
	; Set fcb user # to zero
	lhld info
	mvi m,0
	mvi c,namlen
	call searchi
	call searchn
	call open1 ; Attempt reopen under user zero
	call openx ; openx returns only if unsuccessful
	ret
openx:
	call end$of$dir
	rz
	call getfcba
	mov a,m
	inr a
	jnz openxa
	dcx d
	dcx d
	ldax d
	mov m,a
openxa:
	; open successful
	pop h ; Discard return address
	; Was file opened under user 0 after unsuccessful
	; attempt to open under user n?

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 8333)
	lda high$ext
	ral
	jnc openx0
; CPM3_SD81: [endif] (linea 8337)

	; Is file under user 0 a system file ?

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 8344)

	lhld info
	lxi d,10
	dad d
	mov a,m
	ani 80h
	jnz openx0 ; yes - open successful
	; open fails
	sta high$ext
	jmp lret$eq$ff
openx0:

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 8359)
	call set$lsn
; CPM3_SD81: [endif] (linea 8361)

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

	; Are passwords enabled on drive?
	call get$dir$mode
	ani 80h
	jz openx1a ; no
	; Is this 1st dir fcb?
	call qdirfcb1
	jnz openx0a ; no
	; Does sfcb exist?
	call get$dtba$8
	ora a
	jnz openx0a ; no
	; Is sfcb password mode bd$read or bd$write?
	mov a,m
	ani 0c0h
	jz openx1a ; no
	; Does xfcb exist?
	call xdcnt$eq$dcnt
	call get$xfcb
	jnz openx0b ; yes
	; no - set sfcb password mode to zero
	call restore$dir$fcb
	rz ; (error)
	; Does sfcb still exist?
	call get$dtba$8
	ora a
	jnz openx1a ; no (error)
	; sfcb password mode = 0
	mov m,a
	; update sfcb
	call nowrite
	cz seek$copy
	jmp openx1a
openx0a:
	call xdcnt$eq$dcnt
	; Does xfcb exist?
	call get$xfcb
	jz openx1 ; no
openx0b:
	; yes - check password
	call cmp$pw
	jz openx1
	call chk$pw$error
	lda pw$mode
	ani 0c0h
	jz openx1
	ani 80h
	jnz pw$error
	mvi a,080h
	sta xfcb$read$only
openx1:
	call restore$dir$fcb
	rz ; (error)
openx1a:
	call set$lsn

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 8504)
; CPM3_SD81: [endif] (linea 8505)

	mvi c,01000000b
openx2:
	call qstamp
	cz stamp1
	lxi d,olog
	jmp set$cdisk

func16:
	; Close file
	call reselect

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 8541)
	call set$lsn
	call chek$fcb
	call close
; CPM3_SD81: [endif] (linea 8545)

	lda lret
	inr a
	rz

	jmp bd$flush ; Flush buffers

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 8590)

func17:
	; Search for first occurrence of a file
	xchg
	xra a
csearch:
	push a
	mov a,m
	cpi '?'
	jnz csearch1 ; no reselect if ?
	call curselect
	call noselect0
	mvi c,0
	jmp csearch3
csearch1:
	call getexta
	mov a,m
	cpi '?'
	jz csearch2
	call clr$ext
	call clrmodnum
csearch2:
	call reselectx
	mvi c,namlen
csearch3:
	pop a
	push a
	jz csearch4
	; dcnt = dcnt & 0fch
	lhld dcnt
	push h
	mvi a,0fch
	ana l
	mov l,a
	shld dcnt
	call rd$dir
	pop h
	shld dcnt
csearch4:
	pop a
	lxi h,dir$to$user
	push h
	jz search
	lda searchl
	mov c,a
	call searchi
	jmp searchn

func18:
	; Search for next occurrence of a file name

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	xchg
	shld searcha
; CPM3_SD81: [else] (linea 8645)
; CPM3_SD81: [endif] (linea 8648)

	ori 1
	jmp csearch

func19:
	; Delete a file
;;;	call reselectx	;[JCE] DRI Patch 13
	call patch$1e38
	jmp delete

func20:
	; Read a file
	call reselect
	call check$fcb
	jmp seqdiskread

func21:
	; Write a file
	call reselect
	call check$fcb
	jmp seqdiskwrite

func22:
	; Make a file

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	call get$atts
	sta attributes
; CPM3_SD81: [endif] (linea 8677)

	call clr$ext
	call clrmodnum ; fcb mod = 0
	call reselectx

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 8685)

	call check$wild
	call set$xdcnt ; Reset xdcnt for make

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 8692)

	call open ; Verify file does not already exist

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 8698)

	; Does dir fcb for fcb exist?
	; ora a required to reset carry
	call end$of$dir
	ora a
	jz makea0 ; no
	; Is dir$ext < fcb(ext)?
	call get$dir$ext
	cmp m
	jnc file$exists ; no
makea0:
	push a ; carry set if dir fcb already exists

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 8748)

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	; Is fcb 1st fcb for file?
	call qdirfcb1
	jz makex04 ; yes
	; no - does dir lbl require passwords?
	call get$dir$mode
	ani 80h
	jz makex04
	; no - does xfcb exist with mode 1 or 2 password?
	call get$xfcb
	jz makex04
	; yes - check password
	call chk$xfcb$password1
	jz makex04
	; Verify password error
	call chk$pw$error
	lda pw$mode
	ani 0c0h
	jnz pw$error
makex04:

; CPM3_SD81: [endif] (linea 8771)

	; carry on stack indicates a make not required because
	; of extent folding
	pop a
	cnc make

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 8780)

	; end$of$dir call either applies to above make or open call
	call end$of$dir
	rz ; Return if make unsuccessful

; CPM3_SD81: [if not MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	call set$lsn
; CPM3_SD81: [endif] (linea 8788)

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

	; Are passwords activated by dir lbl?
	call get$dir$mode
	ani 80h
	jz make3a
	; Did user set password attribute?
	lda attributes
	ani 40h
	jz make3a
	; Is fcb file's 1st logical fcb?
	call qdirfcb1
	jnz make3a
	; yes - does xfcb already exist for file
	call xdcnt$eq$dcnt
	call get$xfcb
	jnz make00 ; yes
	; Attempt to make xfcb
	mvi a,0ffh
	sta make$xfcb
	call make
	jnz make00
	; xfcb make failed - delete fcb that was created above
	call search$namlen
	call delete10
	jmp lret$eq$ff ; Return with a = 0ffh

make00:
	call init$xfcb ; Initialize xfcb
	; Get password mode from dma + 8
	xchg
	lhld xdmaad
	lxi b,8
	dad b
	xchg
	ldax d
	ani 0e0h
	jnz make2
	mvi a,080h ; default password mode is bd$read protect
make2:
	sta pw$mode
	; Set xfcb password mode field
	push a
	call getxfcb1
	pop a
	mov m,a
	; Set xfcb password and password checksum
	; Fix hash table and bd$write xfcb
	call set$pw
	mov m,b
	call sdl3
	; Return to fcb
	call restore$dir$fcb
	rz
	; Does sfcb exist?
	mvi c,8
	call getdtba
	ora a
	jnz make3a ; no
	; Place password mode in sfcb if sfcb exists
	lda pw$mode
	mov m,a
	call seek$copy
	call set$lsn
; CPM3_SD81: [endif] (linea 8854)

make3a:
	mvi c,01010000b

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 8876)
	call openx2
	mvi c,00100000b
	call qstamp
	rnz
	call stamp2
	jmp set$filewf
; CPM3_SD81: [endif] (linea 8883)

file$exists:
	mvi a,8
set$aret:
	mov c,a
	sta aret+1
	call lret$eq$ff

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 8895)
	jmp goerr1
; CPM3_SD81: [endif] (linea 8897)

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 8912)

func23:
	; Rename a file
;;;	call reselectx	;[JCE] DRI Patch 13
	call patch$1e38
	jmp rename

func24:
	; Return the login vector
	lhld dlog
	jmp sthl$ret

func25:
	; Return selected disk number
	lda bd$seldsk
	jmp sta$ret

func26:

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 8943)

	; Set the subsequent dma address to info
	xchg
	shld dmaad ; dmaad = info
	jmp setdata ; to data dma address

func27:
	; Return the login vector address
	call curselect
	lhld alloca
	jmp sthl$ret

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 8969)

func28: equ	set$ro ; Write protect current disk

; CPM3_SD81: [endif] (linea 8973)

func29:
	; Return r/o bit vector
	lhld rodsk
	jmp sthl$ret

func30:
	; Set file indicators
	call check$wild
;;;	call reselectx	;[JCE] DRI Patch 13
	call patch$1e38
	call indicators
	jmp copy$dirloc ; lret=dirloc

func31:
	; Return address of disk parameter block
	call curselect
	lhld dpbaddr
sthl$ret:
	shld aret
	ret

func32:
	; Set user code
	lda linfo
	cpi 0ffh
	jnz setusrcode
		; Interrogate user code instead
		lda usrcode
	jmp sta$ret ; lret=usrcode
	setusrcode:
		ani 0fh
	sta usrcode

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 9018)

		ret

func33:
	; Random disk bd$read operation
	call reselect
	call check$fcb
	jmp randiskread ; to perform the disk bd$read

func34:
	; Random disk bd$write operation
	call reselect
	call check$fcb
	jmp randiskwrite ; to perform the disk bd$write

func35:
	; Return file size (0-262,144)
	call reselect
	jmp getfilesize

func36	equ setrandom ; Set random record

func37:
	; Drive reset

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 9048)
	xchg
; CPM3_SD81: [endif] (linea 9050)

reset$37x:
	mov a,l
	cma
	mov e,a
	mov a,h
	cma
	lhld dlog
	ana h
	mov d,a
	mov a,l
	ana e
	mov e,a
	lhld rodsk
	xchg
	shld dlog

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 9071)
	mov a,l
	ana e
	mov l,a
	mov a,h
	ana d
	mov h,a
; CPM3_SD81: [endif] (linea 9078)

	shld rodsk

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 9088)

	; Force select call in next curselect
	mvi a,0ffh
	sta curdsk
	ret

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 9201)

func38	equ	func$ret
func39	equ	func$ret

; CPM3_SD81: [endif] (linea 9206)

func40	equ	func34		; Write random with zero fill

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 9222)

func42	equ	func$ret	; Record lock
func43	equ	func$ret	; Record unlock

; CPM3_SD81: [endif] (linea 9227)

func44:				; Set multi-sector count
	mov a,e
	ora a
	jz lret$eq$ff
	cpi 129
	jnc lret$eq$ff
	sta mult$cnt

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 9243)

	ret

func45:				; Set bdos error mode

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 9267)
	mov a,e
	sta error$mode
; CPM3_SD81: [endif] (linea 9270)

	ret

func46:
	; Get free space
	; Perform temporary select of specified drive
	call tmpselect
	lhld alloca
	xchg ; de = alloc vector addr
	call get$nalbs ; Get # alloc blocks
	; hl = # of allocation vector bytes
	; Count # of bd$true bits in allocation vector
	lxi b,0 ; bc = bd$true bit accumulator
gsp1:	ldax d
gsp2:	ora a
	jz gsp4
gsp3:	rar
	jnc gsp3
	inx b
	jmp gsp2
gsp4:	inx d
	dcx h
	mov a,l
	ora h
	jnz gsp1
	; hl = 0 when allocation vector processed
	; Compute maxall + 1 - bc
	lhld maxall
	inx h
	mov a,l
	sub c
	mov l,a
	mov a,h
	sbb b
	mov h,a
	; hl = # of available blocks on drive
	lda blkshf
	mov c,a
	xra a
	call shl3bv
	; ahl = # of available sectors on drive
	; Store ahl in beginning of current dma
	xchg
	lhld xdmaad
	mov m,e
	inx h
	mov m,d
	inx h
	mov m,a
	ret

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 9326)

func47:				; Chain to program
	lxi h,ccp$flgs
	mov a,m
	ori 80h
	mov m,a
	inr e
	jnz rebootx1
	mov a,m
	ori 40h
	mov m,a
	jmp rebootx1
; CPM3_SD81: [endif] (linea 9339)

func48:				; Flush buffers
	call check$all$media
	call flushf
	call diocomp
flush0:				; Function 98 entry point
	lhld dlog
	mvi a,16
flush1:
	dcr a
	dad h
	jnc flush5
	push a
	push h
	mov e,a
	call tmpselect ; bd$seldsk = e
	lda fx
	cpi 48
	jz flush3
	; Function 98 - reset allocation
	; Copy 2nd ALV over 1st ALV
	call copy$alv
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	jmp patch$2d3a	;[JCE] DRI Patch 13
; CPM3_SD81: [else] (linea 9364)
; CPM3_SD81: [endif] (linea 9366)

flush3:
	call flushx
	; if e = 0ffh then discard buffers after possible bd$flush
	lda linfo
	inr a
	jnz flush4
flush35:
	call discard$data
flush4:
	pop h
	pop a
flush5:
	ora a
	jnz flush1
	ret

bd$flush:
	call flushf
	call diocomp
flushx:
	lda phymsk
	ora a
	rz
	mvi a,4
	jmp deblock$dta

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 9398)

func49: ; Get/Set system control block

	xchg
	mov a,m
	cpi 99
	rnc
	xchg
	lxi h,scb
	add l
	mov l,a
	xchg
	inx h
	mov a,m
	cpi 0feh
	jnc func49$set
	xchg
	mov e,m
	inx h
	mov d,m
	xchg
	jmp sthl$ret
func49$set:
	mov b,a
	inx h
	mov a,m
	stax d
	inr b
	rz
	inx h
	inx d
	mov a,m
	stax d
	ret
; CPM3_SD81: [endif] (linea 9433)

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 9439)

func50:				; Direct bios call
	; de -> function (1 byte)
	;	a  value (1 byte)
	;	bc value (2 bytes)
	;	de value (2 bytes)
	;	hl value (2 bytes)

	lxi h,func50$ret
	push h
	xchg

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	mov a,m
	cpi 27
	rz
	cpi 12
	jnz dir$bios1
	lxi d,dir$bios3
	push d
dir$bios1:
	cpi 9
	jnz dir$bios2
	lxi d,dirbios4
	push d
dir$bios2:

; CPM3_SD81: [endif] (linea 9467)

	push h
	inx h
	inx h
	mov c,m
	inx h
	mov b,m
	inx h
	mov e,m
	inx h
	mov d,m
	inx h
	mov a,m
	inx h
	mov h,m
	mov l,a
	xthl
	mov a,m
	push h
	mov l,a
	add a
	add l

	lxi h,bios

	add l
	mov l,a
	xthl
	inx h
	mov a,m
	pop h
	xthl
	ret

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

dir$bios3:
	mvi a,1
	jmp setbnkf

dir$bios4:
	mov a,l
	ora h
	rz
	xchg
	lxi h,10
	dad d
	mvi m,0 ; Zero login sequence #
	lhld common$base
	call subdh
	xchg
	rnc
	; Copy DPH to common memory
	xchg
	lhld info
	inx h
	push h
	lxi b,25
	call movef
	pop h
	ret
; CPM3_SD81: [endif] (linea 9529)

func50$ret:

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	shld aret
	mov b,a
	lhld info
	mov a,m
	cpi 9
	rz
	cpi 16
	rz
	cpi 20
	rz
	cpi 22
	rz
	mov a,b
	jmp sta$ret
; CPM3_SD81: [else] (linea 9548)
; CPM3_SD81: [endif] (linea 9554)
; CPM3_SD81: [endif] (linea 9555)

func98	equ	flush0			; Reset Allocation

func99:					; Truncate file
	call reselectx
	call check$wild

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	call chk$password
	cnz chk$pw$error
; CPM3_SD81: [endif] (linea 9566)

	mvi c,bd$true
	call rseek
	jnz lret$eq$ff
	; compute dir$fcb size
	call getdptra
	lxi d,reccnt
	call compute$rr ; cba = fcb size
	; Is random rec # >= dir$fcb size
	call get$rra
	call compare$rr
	jc lret$eq$ff ; yes ( > )
	ora d
	jz lret$eq$ff  ; yes ( = )
	; Perform truncate
	call check$rodir ; may be r/o file
	call wrdir ; verify BIOS can bd$write to disk
	call update$stamp ; Set update stamp
	call search$extnum
trunc1:
	jz copy$dirloc
	; is dirfcb < fcb?
	call compare$mod$ext
	jc trunc2 ; yes
	; remove dirfcb blocks from allocation vector
	push a
	mvi c,0
	call scandm$ab
	pop a
	; is dirfcb = fcb?
	jz trunc3 ; yes
	; delete dirfcb
	call getdptra
	mvi m,empty
	call fix$hash
trunc15:
	call wrdir
trunc2:
	call searchn
	jmp trunc1
trunc3:
	call getfcb
	call dm$position
	call zero$dm
	; fcb(extnum) = dir$ext after blocks removed
	call get$dir$ext
	cmp m
	mov m,a
	push a
	; fcb(rc) = fcb(cr) + 1
	call getfcba
	mov a,m
	inr a
	stax d
	; rc = 0 or 128 if dir$ext < fcb(extnum)
	pop a
	xchg
	cnz set$rc3
	; rc = 0 if no blocks remain in fcb
	lda dminx
	ora a
	cz set$rc3
	lxi b,11
	call get$fcb$adds
	xchg
	; reset archive (t3') attribute bit
	mov a,m
	ani 7fh
	mov m,a
	inx h
	inx d
	; dirfcb(extnum) = fcb(extnum)
	ldax d
	mov m,a
	; advance to .fcb(reccnt) & .dirfcb(reccnt)
	inx h
	mvi m,0
	inx h
	inx h
	inx d
	inx d
	inx d
	; dirfcb_rc+dskmap = fcb_rc+dskmap
	mvi c,17
	call move
	; restore non-erased blkidxs in allocation vector
	mvi c,1
	call scandm$ab
	jmp trunc15

get$fcb$adds:
	call getdptra
	dad b
	xchg
	lhld info
	dad b
	ret

compare$mod$ext:
	lxi b,modnum
	call get$fcb$adds
	mov a,m
	ani 3fh
	mov b,a
	; compare dirfcb(modnum) to fcb(modnum)
	ldax d
	cmp b
	rnz ; dirfcb(modnum) ~= fcb(modnum)
	dcx h
	dcx h
	dcx d
	dcx d
	; compare dirfcb(extnum) to fcb(extnum)
	ldax d
	mov c,m
	call compext
	rz ; dirfcb(extnum) = fcb(extnum)
	ldax d
	cmp m
	ret

zero$dm:
	inr a
	lxi h,single
	inr m
	jz zero$dm1
	add a
zero$dm1:
	dcr m
	call getdma
	mov c,a
	mvi b,0
	dad b
	mvi a,16
zero$dm2:
	cmp c
	rz
	mov m,b
	inx h
	inr c
	jmp zero$dm2

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

func100:			; Set directory label
	; de -> .fcb
	;	drive location
	;	name & type fields user's discretion
	;	extent field definition
	;	bit 1 (80h): enable passwords on drive
	;	bit 2 (40h): enable file access
	;	bit 3 (20h): enable file update stamping
	;	bit 4 (10h): enable file create stamping
	;	bit 8 (01h): assign new password to dir lbl
	call reselectx
	lhld info
	mvi m,21h
	mvi c,1
	call search
	jnz sdl0
	call getexta
	mov a,m
	ani 01110000b
	jnz lret$eq$ff
sdl0:
	; Does dir lbl exist on drive?
	lhld info
	mvi m,20h
	mvi c,1
	call set$xdcnt
	call search
	jnz sdl1
	; no - make one
	mvi a,0ffh
	sta make$xfcb
	call make
	rz ; no dir space
	call init$xfcb
	lxi b,24
	call stamp5
	call stamp1
sdl1:
	; Update date & time stamp
	lxi b,28
	call stamp5
	call stamp2
	; Verify password - new dir lbl falls through
	call chk$xfcb$password
	jnz pw$error
	lxi b,0
	call init$xfcb0
	; Set dir lbl dta in extent field
	ldax d
	ori 1h
	mov m,a
	; Low bit of dir lbl data set to indicate dir lbl exists
	; Update drive's dir lbl vector element
	push h
	lhld drvlbla
	mov m,a
	pop h
sdl2:
	; Assign new password to dir lbl or xfcb?
	ldax d
	ani 1
	jz sdl3
	; yes - new password field is in 2nd 8 bytes of dma
	lxi d,8
	call adjust$dmaad
	call set$pw
	mov m,b
	lxi d,-8
	call adjust$dmaad
sdl3:
	call fix$hash
	jmp seek$copy
; CPM3_SD81: [else] (linea 9783)
; CPM3_SD81: [endif] (linea 9788)

func101:
	; Return directory label data
	; Perform temporary select of specified drive
	call tmpselect
	call get$dir$mode
	jmp sta$ret

func102:
	; Read file xfcb
	call reselectx
	call check$wild
	call zero$ext$mod
	call search$namlen
	rz
	call getdma
	lxi b,8
	call zero
	push h
	mvi c,0
	call get$dtba
	ora a
	jnz rxfcb2
	pop d
	xchg
	mvi c,8

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	call move
	ldax d
	jmp rxfcb3
; CPM3_SD81: [else] (linea 9820)
; CPM3_SD81: [endif] (linea 9822)

rxfcb2:
	pop h
	lxi b,8

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	call zero
	call get$xfcb
	rz
	mov a,m
rxfcb3:
	call getexta
	mov m,a
	ret
; CPM3_SD81: [else] (linea 9837)
; CPM3_SD81: [endif] (linea 9839)

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

func103:
	; Write or update file xfcb
	call reselectx
	; Are passwords enabled in directory label?
	call get$dir$mode
	ral
	jnc lret$eq$ff ; no
	call check$wild
	; Save .fcb(ext) & ext
	call getexta
	mov b,m
	push h
	push b
	; Set extent & mod to zero
	call zero$ext$mod
	; Does file's 1st fcb exist in directory?
	call search$namlen
	; Restore extent
	pop b
	pop h
	mov m,b
	rz ; no
	call set$xdcnt
	; Does sfcb exist?
	call get$dtba$8
	ora a
	jz wxfcb5 ; yes
	; No - Does xfcb exist?
	call get$xfcb
	jnz wxfcb1 ; yes
wxfcb0:
	; no - does file exist in directory?
	mvi a,0ffh
	sta make$xfcb
	call search$extnum
	rz
	; yes - attempt to make xfcb for file
	call make
	rz ; no dir space
	; Initialize xfcb
	call init$xfcb
wxfcb1:
	; Verify password - new xfcb falls through
	call chk$xfcb$password
	jnz pw$error
	; Set xfcb options data
	push h
	call getexta
	pop d
	xchg
	mov a,m
	ora a
	jnz wxfcb2
	ldax d
	ani 1
	jnz wxfcb2
	call sdl3
	jmp wxfcb4
wxfcb2:
	ldax d
	ani 0e0h
	jnz wxfcb3
	mvi a,80h
wxfcb3:
	mov m,a
	call sdl2
wxfcb4:
	call get$xfcb1
	dcr a
	sta pw$mode
	call zero$ext$mod
	call search$namlen
	rz
	call get$dtba$8
	ora a
	rnz
	lda pw$mode
	mov m,a
	jmp seek$copy
wxfcb5:
	; Take sfcb's password mode over xfcb's mode
	mov a,m
	push a
	call get$xfcb
	; does xfcb exist?
	pop b
	jz wxfcb0 ; no
	; Set xfcb's password mode to sfcb's mode
	mov m,b
	jmp wxfcb1

; CPM3_SD81: [endif] (linea 9934)

func104:			; Set current date and time

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 9940)
	lxi h,stamp
; CPM3_SD81: [endif] (linea 9942)
	call copy$stamp
	mvi m,0
	mvi c,0ffh
	jmp timef

func105:			; Get current date and time



; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 9954)
	mvi c,0
	call timef
	lxi h,stamp
; CPM3_SD81: [endif] (linea 9958)

	xchg
	call copy$stamp
	ldax d
	jmp sta$ret

copy$stamp:
	mvi c,4
	jmp move ; ret

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 9976)

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

func106:			; Set default password

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 9988)
	lxi h,df$password+7
; CPM3_SD81: [endif] (linea 9990)
	xchg
	lxi b,8
	push h
	jmp set$pw0
; CPM3_SD81: [else] (linea 9995)
; CPM3_SD81: [endif] (linea 9999)

func107:			; Return serial number

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 10006)
	lxi h,serial
; CPM3_SD81: [endif] (linea 10008)

	xchg
	mvi c,6
	jmp move

func108:			; Get/Set program return code

	; Is de = 0ffffh?
	mov a,d
	ana e
	inr a
	lhld clp$errcde
	jz sthl$ret ; yes - return return code
	xchg
	shld clp$errcde
	ret ; no - set return code

goback0:
	lxi h,0ffffh
	shld aret
goback:
	; Arrive here at end of processing to return to user
	lda resel
	ora a
	jz retmon

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 10039)

		lhld info
	lda fcbdsk
	mov m,a ; fcb(0)=fcbdsk
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

		; fcb(7) = fcb(7) | xfcb$read$only
		lxi d,7
	dad d
	lda xfcb$read$only
	ora m
	mov m,a

; CPM3_SD81: [endif] (linea 10053)
; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [else] (linea 10068)
		; fcb(8) = fcb(8) | high$ext
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
		inx h
; CPM3_SD81: [else] (linea 10072)
; CPM3_SD81: [endif] (linea 10075)
		lda high$ext
	ora m
	mov m,a
; CPM3_SD81: [endif] (linea 10079)

;	return from the disk monitor

retmon:
	lhld entsp
	sphl
	lhld aret
	mov a,l
	mov b,h
	ret
;
;	data areas
;
efcb:	db	empty	; 0e5=available dir entry
rodsk:	dw	0	; bd$read only disk vector
dlog:	dw	0	; logged-in disks

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 10104)

; CPM3_SD81: [if not BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 10111)

; CPM3_SD81: [if not MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

buffa:	ds	word	; pointer to directory dma address

; CPM3_SD81: [endif] (linea 10117)

;
;	curtrka - alloca are set upon disk select
;	(data must be adjacent, do not insert variables)
;	(address of translate vector, not used)
cdrmaxa:ds	word	; pointer to cur dir max value (2 bytes)
curtrka:ds	word	; current track address (2)
curreca:ds	word	; current record address (3)
drvlbla:ds	word	; current drive label byte address (1)
lsn$add:ds	word	; login sequence # address (1)
			; +1 -> bios media change flag (1)
dpbaddr:ds	word	; current disk parameter block address
checka: ds	word	; current checksum vector address
alloca: ds	word	; current allocation vector address
dirbcba:ds	word	; dir bcb list head
dtabcba:ds	word	; data bcb list head
hash$tbla:
	ds	word	; directory hash table address
	ds	byte	; directory hash table bank

addlist equ	$-dpbaddr	; address list size

;
;	       buffer control block format
;
; bcb format : drv(1) || rec(3) || pend(1) || sequence(1) ||
;	       0	 1	   4	      5
;
;	       track(2) || sector(2) || buffer$add(2) ||
;	       6	   8		10
;
;	       bank(1) || link(2)
;	       12	  13
;

;	sectpt - offset obtained from disk parm block at dpbaddr
;	(data must be adjacent, do not insert variables)
sectpt: ds	word	; sectors per track
blkshf: ds	byte	; block shift factor
blkmsk: ds	byte	; block mask
extmsk: ds	byte	; extent mask
maxall: ds	word	; maximum allocation number
dirmax: ds	word	; largest directory number
dirblk: ds	word	; reserved allocation bits for directory
chksiz: ds	word	; size of checksum vector
offset: ds	word	; offset tracks at beginning
physhf: ds	byte	; physical record shift
phymsk: ds	byte	; physical record mask
dpblist equ	$-sectpt	; size of area
;
;	local variables
;
drec		ds	word	; directory record number
blk$off:	ds	byte	; record offset within block
last$off:	ds	byte	; last offset within new block
last$drive:	ds	byte	; drive of last new block
last$block:	ds	word	; last new block

; The following two variables are initialized as a pair on entry

dir$cnt:	ds	byte	; direct i/o count
mult$num:	ds	byte	; multi-sector number

tranv:	ds	word	; address of translate vector
lock$unlock:
make$flag:
rmf:	ds	byte	; bd$read mode flag for open$reel
incr$pdcnt:
dirloc: ds	byte	; directory flag in rename, etc.
free$mode:
linfo:	ds	byte	; low(info)
dminx:	ds	byte	; local for diskwrite

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 10195)
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

searcha:ds	word	; search address

; CPM3_SD81: [endif] (linea 10200)

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

save$xfcb:
	ds	byte	; search xfcb save flag

; CPM3_SD81: [endif] (linea 10207)

single: ds	byte	; set bd$true if single byte allocation map

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 10215)

bd$seldsk: ds	byte	; disk on entry to bdos
rcount: ds	byte	; record count in current fcb
extval: ds	byte	; extent number and extmsk
save$mod:
	ds	byte	; open$reel module save field

vrecord:ds	byte	; current virtual record

; CPM3_SD81: [if not MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

curdsk: db	0ffh	; current disk

; CPM3_SD81: [endif] (linea 10229)

adrive: db	0ffh	; current blocking/deblocking disk
arecord:ds	word	; current actual record
	ds	byte

save$ranr:	ds	3	; random record save area
arecord1:	ds	word	; current actual block# * blkmsk
attributes:	ds	byte	; make attribute hold area
readf$sw:	ds	byte	; BIOS bd$read/bd$write switch

;******** following variable order critical *****************

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 10247)

high$ext:	ds	byte	; fcb high ext bits

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

xfcb$read$only: ds	byte	; xfcb bd$read only flag

; CPM3_SD81: [endif] (linea 10255)
; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 10281)

;	local variables for directory access
dptr:	ds	byte	; directory pointer 0,1,2,3

save$hash:	ds	4	; hash code save area

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

copy$cr$init:	ds	byte	; copy$cr$only initialization value

; CPM3_SD81: [else] (linea 10292)
; CPM3_SD81: [endif] (linea 10297)

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 10306)

search$user0:	ds	byte	; search user 0 for file (open)

user0$pass:	ds	byte	; search user 0 pass flag

fcbdsk:		ds	byte	; disk named in fcb

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 10319)

log$fxs:db	15,16,17,19,22,23,30,35,99,100,102,103,0
rw$fxs: db	20,21,33,34,40,41,0
sc$fxs: db	16,18,0

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 10329)
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

pw$fcb:		ds	12	;1 |
		db	0	;2 |
pw$mode:	db	0	;3 |- Order critical
		db	0	;4 |
		db	0	;5 |

df$password:	ds	8

; CPM3_SD81: [if MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 10342)
; CPM3_SD81: [endif] (linea 10343)

phy$off:	ds	byte
curbcba:	ds	word

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

lastbcba:	ds	word
rootbcba:	ds	word
emptybcba:	ds	word
seqbcba:	ds	word
buffer$bank:	ds	byte

; CPM3_SD81: [endif] (linea 10356)

track:		ds	word
sector:		ds	word

;	**************************
;	Blocking/Deblocking Module
;	**************************

deblock$dta:
	lhld dtabcba

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	cpi 4
	jnz deblock
deblock$flush:
	; de = addr of 1st bcb
	mov e,m
	inx h
	mov d,m
	; Search for dirty bcb with lowest track #
	lxi h,0ffffh
	shld track
	xchg
deblock$flush1:
	; Does current drive own bcb?
	lda adrive
	cmp m
	jnz deblock$flush2 ;no
	; Is bcb's buffer pending?
	xchg
	lxi h,4
	dad d
	mov a,m
	xchg
	inr a
	jnz deblock$flush2 ; no
	; Is bcb(6) < track?
	push h
	inx d
	inx d
	xchg
	mov e,m
	inx h
	mov d,m
	; Subdh computes hl = de - hl
	lhld track
	call subdh
	pop h
	jnc deblock$flush2 ; no
	; yes - track = bcb(6) , sector = addr(bcb)
	xchg
	shld track
	xchg
	shld sector
deblock$flush2:
	; Is this the last bcb?
	call get$next$bcba
	jnz deblock$flush1 ; no - hl = addr of next bcb
	; Does track = ffff?
	lxi h,track
	call test$ffff
	rz ; yes - no bcb to bd$flush
	; Flush bcb located by sector
	lhld sector
	xra a
	mvi a,4
	call deblock
	lhld dtabcba
	jmp deblock$flush ; Repeat until no bcb's to bd$flush
; CPM3_SD81: [endif] (linea 10426)

deblock:

	; BDOS Blocking/Deblocking routine
	; a = 1 -> bd$read command
	; a = 2 -> bd$write command
	; a = 3 -> locate command
	; a = 4 -> bd$flush command
	; a = 5 -> directory update

	push a ; Save z flag and deblock fx

	; phy$off = low(arecord) & phymsk
	; low(arecord) = low(arecord) & ~phymsk
	call deblock8
	lda arecord
	mov e,a
	ana b
	sta phy$off
	mov a,e
	ana c
	sta arecord

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	pop a
	push a
	cnz get$bcba
; CPM3_SD81: [endif] (linea 10454)

	shld curbcba
	call getbuffa
	shld curdma
	; hl = curbcba, de = .adrive, c = 4
	call deblock9
	; Is BCB discarded?
	mov a,m
	inr a
	jz deblock2 ; yes
	; Is command bd$flush?
	pop a
	push a
	cpi 4
	jnc deblock1 ; yes
	; Is referenced physical record already in buffer?

;;;	call compare	;[JCE] DRI patch 7
	call patch$1e0c

	jz deblock45 ; yes
	xra a
deblock1:
	; Does buffer contain an updated record?
	call deblock10
	cpi 5
	jz deblock15
	mov a,m
	ora a
	jz deblock2 ; no
deblock15:
	; Reset record pending flag
	mvi m,0
	; Save arecord
	lhld arecord
	push h
	lda arecord+2
	push a
	; Flush physical record buffer
	call deblock9
	xchg
	call move
	; Select drive to be flushed
	lxi h,curdsk
	lda adrive
	cmp m
	cnz disk$select1
	; Write record if drive logged-in
	mvi a,1
	cz deblock$io
	; Restore arecord
	pop b
	pop d
	call set$arecord
	; Restore selected drive
	call curselect
deblock2:
	; Is deblock command bd$flush | dir bd$write?
	pop a
	cpi 4
	rnc ; yes - return
	; Is deblock command bd$write?
	push a
	cpi 2
	jnz deblock25 ; no
	; Is blk$off < last$off
	lxi h,last$off
	lda blk$off
	cmp m
	jnc deblock3 ; no
deblock25:
	; Discard BCB on bd$read operations in case
	; I/O error occurs
;;;	lhld curbcba		;[JCE] DRI Patch 7
	call patch$1e1c
	mvi m,0ffh
	; Read physical record buffer
	mvi a,2
	jmp deblock35
deblock3:
	; last$off = blk$off + 1
	inr a
	mov m,a
	; Place track & sector in bcb
	xra a
deblock35:
	call deblock$io
deblock4:
	call deblock9 ; phypfx = adrive || arecord
	call move
	mvi m,0 ; zero pending flag

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	; Zero logical record sequence
	inx h
	call set$bcb$seq
; CPM3_SD81: [endif] (linea 10551)

deblock45:
	; recadd = phybuffa + phy$off*80h
	lda phy$off
	inr a
	lxi d,80h
	lxi h,0ff80h
deblock5:
	dad d
	dcr a
	jnz deblock5
	xchg
	lhld curdma
	dad d
	; If deblock command = locate then buffa = recadd; return
	pop a
	cpi 3
	jnz deblock6
	shld buffa
	ret
deblock6:
	xchg
	lhld dmaad
	lxi b,80h
	; If deblock command = bd$read
	cpi 1

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	jnz deblock7
	; then move to tpa
	lda common$base+1
	dcr a
	cmp d
	jc move$tpa
	lda buffer$bank
	mov c,a
	mvi b,1
	call deblock12
	lxi b,80h
	jmp move$tpa
deblock7:

; CPM3_SD81: [else] (linea 10594)
; CPM3_SD81: [endif] (linea 10596)

	; else move from dma
	xchg

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	lda common$base+1
	dcr a
	cmp h
	jc deblock75
	lda buffer$bank
	mov b,a
	mvi c,1
	call deblock12
	lxi b,80h
deblock75:

; CPM3_SD81: [endif] (linea 10613)

	call move$tpa
	; Set physical record pending flag for bd$write command
	call deblock10
	mvi m,0ffh
	ret

deblock8:
	lda phymsk
	mov b,a
	cma
	mov c,a
	ret

deblock9:
	lhld curbcba
	lxi d,adrive
	mvi c,4
	ret

deblock10:
	lxi d,4
deblock11:
	lhld curbcba
	dad d
	ret

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

deblock12:
	push h
	push d
	call xmovef
	pop d
	pop h
	ret
; CPM3_SD81: [endif] (linea 10650)

deblock$io:
	; a = 0 -> seek only
	; a = 1 -> bd$write
	; a = 2 -> bd$read
	push a
	call seek

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	lda buffer$bank
	call setbnkf
; CPM3_SD81: [endif] (linea 10662)

	mvi c,1
	pop a
	dcr a
	jz wrbuff
	cp rdbuff
	; Move track & sector to bcb
	call deblock10
	inx h
	inx h
	lxi d,track
	mvi c,4
	jmp move

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

get$bcba:
;;;	shld rootbcba	;[JCE] DRI Patch 13
	call patch$2d30
	lxi d,-13
	dad d
	shld lastbcba
	call get$next$bcba
	push h
	; Is there only 1 bcb in list?
	call get$next$bcba
	pop h
	rz ; yes - return
	xchg
	lxi h,0
	shld emptybcba
	shld seqbcba
	xchg
get$bcb1:
	; Does bcb contain requested record?
	shld curbcba
	call deblock9
	call compare
	jz get$bcb4 ; yes
	; Is bcb discarded?
	lhld curbcba
	mov a,m
	inr a
	jnz get$bcb11 ; no
	xchg
	lhld lastbcba
	shld emptybcba
	jmp get$bcb14
get$bcb11:
	; Does bcb contain record from current disk?
	lda adrive
	cmp m
	jnz get$bcb15 ; no
	xchg
	lxi h,5
	dad d
	lda phy$msk
	; Is phy$msk = 0?
	ora a
	jz get$bcb14 ; yes
	; Does bcb(5) [bcb sequence] = phymsk?
	cmp m
	jnz get$bcb14 ; no
;;;	lhld seqbcba	;[JCE] DRI Patch 13
;;;	mov a,l
;;;	ora h
	lda patch$2d39
	ora a
	nop
	jnz get$bcb14
	lhld lastbcba
	shld seqbcba
get$bcb14:
	xchg
get$bcb15:
	; Advance to next bcb - list exhausted?
	push h
	call get$next$bcba
	pop d
	jz get$bcb2 ; yes
	xchg
	shld lastbcba
	xchg
	jmp get$bcb1
get$bcb2:
	; Matching bcb not found
	; Was a sequentially accessed bcb encountered?
;;;	lhld seqbcba	;[JCE] DRI Patch 13
	lhld emptybcba

	mov a,l
	ora h
	jnz get$bcb25 ; yes
	; Was a discarded bcb encountered?
;;;	lhld emptybcba	;[JCE] DRI Patch 13
	lhld seqbcba

	mov a,l
	ora h
	jz get$bcb3 ; no
get$bcb25:
	shld lastbcba
get$bcb3:
	; Insert selected bcb at head of list
	lhld lastbcba
	call get$next$bcba
	shld curbcba
	call get$next$bcba
	xchg
	call last$bcb$links$de
	lhld rootbcba
	mov e,m
	inx h
	mov d,m
	lhld curbcba
	lxi b,13
	dad b
	mov m,e
	inx h
	mov m,d
	lhld curbcba
	xchg
	lhld rootbcba
	mov m,e
	inx h
	mov m,d
	xchg
	ret
get$bcb4:
	; BCB matched arecord
	lhld curbcba
	lxi d,5
	dad d
	; Does bcb(5) = phy$off?
	lda phy$off
	cmp m
	jz get$bcb5 ; yes
	; Does bcb(5) + 1 = phy$off?
	inr m
	cmp m
	jz get$bcb5 ; yes
	call set$bcb$seq
get$bcb5:
	; Is bcb at head of list?
	lhld curbcba
	xchg
	lhld rootbcba
	mov a,m
	inx h
	mov l,m
	mov h,a
	call subdh
	ora l
	xchg
	rz ; yes
	jmp get$bcb3 ; no - insert bcb at head of list

last$bcb$links$de:
	lhld lastbcba
	lxi b,13
	dad b
	mov m,e
	inx h
	mov m,d
	ret

get$next$bcba:
	lxi b,13
	dad b
	mov e,m
	inx h
	mov d,m
	xchg
	mov a,h
	ora l
	ret

set$bcb$seq:
	lda phy$off
	mov m,a
	ora a
	rz
	lda phy$msk
	inr a
	mov m,a
	ret

; CPM3_SD81: [endif] (linea 10850)

; CPM3_SD81: [if not MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
; CPM3_SD81: [if not BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 10997)
; CPM3_SD81: [endif] (linea 10998)

;	************************
;	Directory Hashing Module
;	************************

; Hash format
; xxsuuuuu xxxxxxxx xxxxxxxx ssssssss
; x = hash code of fcb name field
; u = low 5 bits of fcb user field
;     1st bit is on for XFCB's
; s = shiftr(mod || ext,extshf)

; CPM3_SD81: [if not BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> inactivo
; CPM3_SD81: [endif] (linea 11015)

init$hash:
	; de = .hash table entry
	; hl = .dir fcb
	push h
	push d
	call get$hash
	; Move computed hash to hash table entry
	pop h
	lxi d,hash
	lxi b,4

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	lda hash$tbla+2
	call move$out
; CPM3_SD81: [else] (linea 11031)
; CPM3_SD81: [endif] (linea 11033)

	; Save next hash table entry address
	shld arecord1
	; Restore dir fcb address
	pop h
	ret

set$hash:
	; Return if searchl = 0
	ora a
	rz
	; Is searchl < 12 ?
	cpi 12
	jc set$hash2 ; yes - hashl = 0
	; Is searchl = 12 ?
	mvi a,2
	jz set$hash1 ; yes - hashl = 2
	mvi a,3 ; hashl = 3
set$hash1:
	sta hashl
	xchg
	; Is dir hashing invoked for drive?
	call test$hash
	rz ; no
	xchg
	lda fx
	cpi 16
	jz get$hash ; bdos fx = 16
	cpi 35
	jz set$hash15
	cpi 20
	jnc get$hash ; bdos fx = 20 or above
set$hash15:
	mvi a,2
	sta hashl ; bdos fx = 15,17,18,19, or 35
	; if fcb wild then hashl = 0, hash = fcb(0)
	;	      else hashl = 2, hash = get$hash
	push h
	call chk$wild
	pop h
	jnz get$hash
set$hash2:
	xra a
	sta hashl
	; jmp get$hash

get$hash:
	; hash(0) = fcb(0)
	mov a,m
	sta hash
	inx h
	xchg
	; Don't compute hash for dir lbl & sfcb's
	lxi h,0
	ani 20h
	jnz get$hash6
	; b = 11, c = 8, ahl = 0
	; Compute fcb name hash (000000xx xxxxxxxxx xxxxxxxx) (ahl)
	lxi b,0b08h
get$hash1:
	; Don't shift if fcb(8)
	dcr c
	push b
	jz get$hash3
	; Don't shift if fcb(6)
	dcr c
	dcr c
	jz get$hash3
	; ahl = ahl * 2
	dad h
	adc a
	push a
	mov a,b
	; is b odd?
	rar
	jc get$hash4 ; yes
	; ahl = ahl * 2 for even fcb(i)
	pop a
	dad h
	adc a
get$hash3:
	push a
get$hash4:
	; a = fcb(i) & 7fh - 20h divided by 2 if even
	ldax d
	ani 7fh
	sui 20h
	rar
	jnc get$hash5
	ral
get$hash5:
	; ahl = ahl + a
	mov c,a
	mvi b,0
	pop a
	dad b
	aci 0
	pop b
	; advance to next fcb char
	inx d
	dcr b
	jnz get$hash1
get$hash6:
	; ahl = 000000xx xxxxxxxx xxxxxxxx
	; Store low 2 bytes of hash
	shld hash+1
	lxi h,hash
	; hash(0) = hash(0) (000uuuuu) | xx000000
	ani 3
	rrc
	rrc
	ora m
	mov m,a
	; Does fcb(0) = e5h, 20h, or 21h?
	ani 20h
	jnz get$hash9 ; yes
	; bc = 00000mmm mmmeeeee, m = module #, e = extent
	ldax d
	ani 1fh
	mov c,a
	inx d
	inx d
	ldax d
	ani 3fh
	rrc
	rrc
	rrc
	mov d,a
	ani 7
	mov b,a
	mov a,d
	ani 0e0h
	ora c
	mov c,a
	; shift bc right by # of bits in extmsk
	lda extmsk
get$hash7:
	rar
	jnc get$hash8
	push a
	mov a,b
	rar
	mov b,a
	mov a,c
	rar
	mov c,a
	pop a
	jmp get$hash7
get$hash8:
	; hash(0) = hash(0) (xx0uuuuu) | 00s00000
	mov a,b
	ani 1
	rrc
	rrc
get$hash9:
	rrc
	ora m
	mov m,a
	; hash(3) = ssssssss
	lxi d,3
	dad d
	mov m,c
	ret

test$hash:
	lhld hash$tbla
	mov a,l
	ora h
	inr a
	ret

search$hash:
	; Does hash table exist for drive?
	call test$hash
	rz ; no
	; Has dir hash search been disabled?
	lda hashl
	inr a
	rz ; yes
	; Is searchl = 0?
	lda searchl
	ora a
	rz ; yes
	; hashmx = cdrmaxa if searchl ~= 1
	;	   dir$max if searchl = 1
	lhld cdrmaxa
	mov e,m
	inx h
	mov d,m
	xchg
	dcr a
	jnz search$h0
	lhld dir$max
search$h0:
	shld hashmx

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	; call search$hash in resbdos, a = bank, hl = hash tbl addr
	lda hash$tbla+2
	lhld hash$tbla
	call srch$hash
	; Was search successful?
	jnz search$h1 ; no
	; Is directory bd$read required?
	lda rd$dir$flag
	ora a
	mvi c,0
	cnz r$dir2 ; yes if Z flag reset
	; Is function = 18?
	lda fx
	sui 18
	rz ; Never reset dcnt for fx 18
	; Was media change detected by above bd$read?
	lda hashl
	inr a
	cz setenddir ; yes
	xra a
	ret ; search$hash successful
search$h1:
	; Was search initiated from beginning of directory?
	call end$of$dir
	rnz ; no
	; Is bdos fx = 15,17,19,22,23,30?
	call tst$log$fxs
	rnz ; no
	; Disable hash & return successful
	mvi a,0ffh
	sta hashl
	lhld cdrmaxa
	mov e,m
	inx h
	mov d,m
	xchg
	dcx h
	call set$dcnt$dblk1
	xra a
	ret
; CPM3_SD81: [else] (linea 11271)
; CPM3_SD81: [endif] (linea 11442)

fix$hash:
	call test$hash
	rz
	lxi h,save$hash
	lxi d,hash
	lxi b,4
	push h
	push d
	push b
	call movef
	lhld hash$tbla
	push h
	call get$dptra
	call get$hash
	lhld dcnt
	dad h
	dad h
	pop d
	dad d
	pop b
	pop d
	push d
	push b

; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
	lda hash$tbla+2
	call move$out
; CPM3_SD81: [else] (linea 11471)
; CPM3_SD81: [endif] (linea 11473)

	pop b
	pop h
	pop d
	jmp movef

; CPM3_SD81: [if not MPM] resuelto en preprocesado (BANKED=1,MPM=0) -> activo
; CPM3_SD81: [if BANKED] resuelto en preprocesado (BANKED=1,MPM=0) -> activo

patch$1dfd:			;[JCE] DRI Patch 7
	lda	chksiz+1
	ral
	jc	get$dir$ext
	mvi	a,0ffh
	sta	patch$1e24
	jmp	get$dir$ext

patch$1e0c:
	cpi	3
	jnz	compare
	lda	patch$1e24
	inr	a
	jnz	compare
	pop	h
	jmp	deblock25

patch$1e1c:
	xra	a
	sta	patch$1e24
	lhld	curbcba
	ret

patch$1e24:
	db	0

patch$1e25:
	lxi	h,0
	shld	conbuffadd
	shld	ccp$conbuff
	dcx	h
	dcx	h
	ret

patch$2d30:
	shld rootbcba
	sui 3
	sta patch$2d39
	ret

patch$2d39:
	db	0

patch$2d3a:
	call	patch$2d43
	jmp	flush4

patch$2d40:
	call	copy$alv
patch$2d43:
	lhld	dtabcba
	mov	a,l
	ana	h
	inr	a
	rz
patch$2d4a:
	mov	e,m
	inx	h
	mov	d,m
	mov	a,d
	ora	e
	rz
	lxi	h,adrive
	ldax	d
	cmp	m
	jnz	patch$2d63
	lxi	h,4
	dad	d
	mvi	a,0ffh
	cmp	m
	jnz	patch$2d63
	stax	d
patch$2d63:
	lxi	h,0dh
	dad	d
	jmp	patch$2d4a

patch$2d6a:
	call	copy$alv
	lhld	lsn$add
	mov	a,m
	ora	a
	rnz	
	mvi	m,2
	ret

patch$1e31:
	call	check$write
	lxi	h,xdcnt
	ret

patch$1e38:
	call	reselectx
	jmp	check$write

patch$1e3e:
	call	setfwf
	jmp	search$namlen

last:

; CPM3_SD81: bug real de la fuente DRI (esta en la version original sin
; tocar, BDOS30.ASM lineas 6231/6240): falta sumar "base" -- calcula
; bien un TAMAÑO relativo (last-base) pero luego lo usa tal cual como
; direccion ABSOLUTA de destino del "org", sin volver a sumar "base".
; Invisible mientras base=$0000 (sumar 0 no cambia nada) -- salio a la
; luz al mover la BDOS a $8800 (confirmado en hardware: RESBDOS.ASM
; aterrizaba en $2E00 en vez de justo detras de esto, ~$B600).
	org	base + (((last-base)+255) and 0ff00h) - 1
	db	0

; CPM3_SD81: [endif] (linea 11587)

; CPM3_SD81: [else] (linea 11589)
; CPM3_SD81: [endif] (linea 11631)

; CPM3_SD81: alias para erratas de transcripcion en la fuente DRI/
; Caldera (un '$' insertado o que falta entre la definicion real y las
; llamadas, en un sentido u otro -- ver memory_map.md). No se toca el
; codigo disperso, solo se anade el nombre que faltaba. Movido aqui
; (al final del fichero, backward-reference puro) porque como forward
; reference desestabilizaba la resolucion de direcciones -- ver la
; nota junto a "maclib makedate", mas arriba.
ccpflgs	equ	ccp$flgs
common$base	equ	commonbase
comp$cdr	equ	compcdr
copy$dir$loc	equ	copy$dirloc
dir$max	equ	dirmax
dircnt	equ	dir$cnt
diskwrite0	equ	disk$write0
dta$bcba	equ	dtabcba
error$mode	equ	errormode
get$dm	equ	getdm
get$dptra	equ	getdptra
get$exta	equ	getexta
getbuffa	equ	get$buffa
getdtba	equ	get$dtba
gets1	equ	get$s1
getxfcb1	equ	get$xfcb1
hashtbla	equ	hash$tbla
lastdrive	equ	last$drive
mult$cnt	equ	multcnt
mult$iof	equ	multiof
parse$pw	equ	parsepw
phy$msk	equ	phymsk
rd$dir	equ	rddir
reset37x	equ	reset$37x
save$pos	equ	SAVEPOS
search$n	equ	searchn
seek$dir	equ	seekdir
set$lret1	equ	setlret1
testvector	equ	test$vector
user0pass	equ	user0$pass
; "bios" (direccion base de una tabla de saltos de zancada fija, usada
; solo por la funcion 50 "Direct BIOS call" para calcular entradas por
; aritmetica de offset) no tiene equivalente real: nuestra tabla de
; saltos (bank.z80) no es de zancada fija (cada entrada mide lo que
; mide, no siempre 3 B). func50 queda roto a proposito -- es una
; funcion BDOS rara, de muy bajo uso (acceso directo al BIOS saltandose
; la BDOS). Alias solo para que compile; NO llamar a funcion 50.
bios	equ	?boot
; xdmaad y srch$hash van en bdos_full.z80, DESPUES de "include
; RESBDOS.ASM" -- apuntan a nombres que RESBDOS.ASM define (xdmaadd,
; rb$search$hash), y como referencia hacia delante (RESBDOS.ASM va
; despues de este fichero) desestabilizaban la resolucion de
; direcciones (confirmado: tambien afectaba a "bdose2", sin relacion
; aparente -- ver la nota general de mas arriba, junto a "maclib
; makedate").
set$alloc$bit	equ	setallocbit
search$loop	equ	searchloop
delete$10	equ	delete10
setenddir	equ	set$end$dir
read$n0	equ	readn0
do$new$line	equ	do$newline
out$delim	equ	outdelim
; dirbios4 (BDOS30.ASM, funcion 50 "Direct BIOS call", rara vez usada):
; falta directamente en la fuente -- solo existen dir$bios1/2/3. Por la
; logica del salto (cpi 9 / jnz dir$bios2 -- si es igual, cae directo
; aqui), lo mas razonable es que apunte a dir$bios2; sin verificar contra
; hardware real, es una funcion de muy bajo uso.
dirbios4	equ	dir$bios2

		end
