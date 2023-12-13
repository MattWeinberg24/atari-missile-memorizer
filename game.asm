;------------------------------------------------
;
; "Missile Memorizer"
; by Matt Weinberg
; CSE 337 FL 2023
; Washington University in St. Louis
;
;------------------------------------------------
	processor 	6502
	include 	vcs.h
	include 	macro.h

;------------------------------------------------
; Constants
;------------------------------------------------
SEQUENCE_SIZE = #19
; COLORS
BLACK = #$00
WHITE = #$0E
LEVEL_COLOR = #$B4
HEADER_COLOR = #$77
FIELD_COLOR = #$A2
PLAYER_COLOR = #$CC
CORRECT_COLOR = #$C6
WRONG_COLOR = #$40
; HEIGHTS
LEVEL_DIGIT_HEIGHT = #4
LEVEL_HEIGHT = #15
FIELD_HEIGHT = #89
BAND_HEIGHT = #22
PLAYER_HEIGHT = #8
; POSITIONS
PLAYER_START_Y = #50
; LIMITS
TOP_LIMIT = #$50
BOTTOM_LIMIT = #$10
; TIMES
HIT_DURATION = #40
BREAK_DURATION = #20
; SOUND
VOLUME = #$04
NORMAL_CONTROL = %00000001
WRONG_CONTROL = #%00000011

;------------------------------------------------
; RAM
;------------------------------------------------
    SEG.U   variables
    ORG     $80

bgcolor		.byte
; GAME VARIABLES
level 		.byte ; 1 means 1 target, and so on. Behavior defined for levels 1-19
frame		.byte ; frame counter
seed 		.byte ; random seed. initially equal to frame counter
phase		.byte ; 0 if replay, 1 if player
levelend 	.byte ; 0 if not, 1 if yes
gameover	.byte ; 0 if not, 1 if yes
idle 		.byte ; 0 if not, 1 if yes
; FIELD VARIABLES
field		.byte ; current y-value in the field
band 		.byte ; current band index (top=4, bottom=1)
; SEQUENCE VARIABLES
seq			 ds #SEQUENCE_SIZE ; holds the complete sequence
curr		.byte 			   ; index of element in the sequence currently being "tested" or "replayed"
attempt		.byte			   ; value guessed by the player, or currently being replayed
; PLAYER VARIABLES (P0)
p0gfx		.byte
p0gfxIndex  .byte
p0y			.byte
p0v			.byte
p0fire		.byte
p0left		.byte
; TARGET VARIABLES (P1)
p1gfx		.byte
p1gfxIndex  .byte
p1y			.byte
p1hit		.byte
hittimer    .byte ; framecounter for when a target "lights up"
breaktimer  .byte ; framecounter for the short "break" in between targets lighting up in the replay
hitcolor 	.byte ; green for correct/replay, red for incorrect
; MISSILE VARIABLES (M0)
m0			.byte
m0y			.byte
m0velocity  .byte
m0band		.byte ; the band index (top=4, bottom=1) the missile was fired in
; LEVEL DISPLAY VARIABLES
levelGfx	ds 2


	echo [(* - $80)]d, " RAM bytes used"

;------------------------------------------------
; Start of ROM
;------------------------------------------------
	SEG   Bank0
	ORG   $F000       	; 4k ROM start point

	
Start 
	CLEAN_START			; Clear RAM and Registers
	lda #0
	sta frame ; framecounter starts before reset, as it determines the seed
	lda #1
	sta idle ; game starts in idle state until reset is pressed
Reset
	; Sound Init
	lda	#VOLUME
	sta	AUDV0
	sta	AUDV1
	lda #0
	sta AUDC0
	sta AUDC1
	sta AUDF0
	sta AUDF1
	; Game Init
	lda #1 ; TEST. SHOULD BE 1 TO START
	sta level
	lda #0
	sta phase ; Replay = 0 (start), Player = 1
	sta levelend
	sta curr
	; Player Init
	lda #PLAYER_START_Y
	sta p0y
	lda #PLAYER_COLOR
	sta COLUP0
	; initialize Missile
	lda	#0				
	sta	RESMP1
	sta RESMP0
	lda	#%00010101 ; double width, 2-color-clock missiles
	sta	NUSIZ0
	sta	NUSIZ1
	; Target Init
	lda #0
	sta p1hit
	sta hittimer
	lda #1 ; game starts on break
	sta breaktimer
;-----RNG Init Begin-----
RNGInit
	lda idle
	bne .endRNGInit ; wait until idle = 0 to generate sequence and "start" the game
	lda frame
	sta seed 		; the seed is the current framecounter upon reset
	jsr GenerateSequence
.endRNGInit
;-----RNG Init End-----

;------------------------------------------------
; Vertical Blank
;------------------------------------------------
MainLoop
	;***** Vertical Sync routine
	lda	#2
	sta VSYNC 	; begin vertical sync, hold for 3 lines
	sta WSYNC 	; 1st line of vsync
	sta WSYNC 	; 2nd line of vsync
	sta WSYNC 	; 3rd line of vsync
	lda #43   	; set up timer for end of vblank
	sta TIM64T
	lda #0
	sta VSYNC 	; turn off vertical sync - also start of vertical blank

	; Band Init (per-frame)
	lda #4
	sta band
	lda #0
	sta GRP0
	sta GRP1
	
	inc frame ; Increment Framecounter

	; Level Display Init (per-frame)
	ldx level
	lda DigitOffsets,x
	sta levelGfx
	lda #>Digits 
	sta levelGfx+1
	
;-----HITTIMER START-----
CheckHitTimer
	lda hittimer
	beq .endCheckHitTimer ; if timer = 0, nothing chosen
	inc hittimer ; otherwise increment

	; Apply Sound Start
	ldx attempt
	lda #NORMAL_CONTROL
	sta AUDC0
	lda SoundFreqs-1,x
	sta AUDF0
	lda gameover
	beq .continueCheckHitTimer
	lda #WRONG_CONTROL ; add extra sound channel if player is wrong
	sta AUDC1
	sta AUDF1
	; Apply Sound End
.continueCheckHitTimer
	lda hittimer
	cmp #HIT_DURATION ; if reached hit duration...
	bne .endCheckHitTimer
	lda #0 ; set timer back to 0
	sta hittimer
	sta AUDC0 ; reset sound registers
	sta AUDC1
	sta AUDF0
	sta AUDF1
	
	lda #1
	sta breaktimer ; break starts after hit ends
.endCheckHitTimer
;-----HITTIMER END-----

;-----RESET SWITCH BEGIN-----
CheckResetSwitch
	lda	#%00000001
	bit	SWCHB
	bne	.endCheckResetSwitch
	lda #0
	sta idle ; go out of idle state once reset is pressed
	jmp	Reset
.endCheckResetSwitch
;-----RESET SWITCH END-----

;-----INPUT BEGIN-----
	lda phase
	beq .endCheckJoy0Right
	lda levelend
	bne .endCheckJoy0Right
CheckJoy0Fire
	lda	#%10000000
	bit	INPT4
	bne	.endCheckJoy0Fire
	lda #1
	sta p0fire
.endCheckJoy0Fire
CheckJoy0Up
	lda	#%00010000			; pattern to match for joystick
	bit	SWCHA				; bit comparison on SWCHA (see Stella Programmers guide)
	bne	.endCheckJoy0Up		; skip what follows if the bit pattern doesn't match
	lda	p0y					
	cmp	#TOP_LIMIT			; if y is already max (remember we count down!)
	beq	.endCheckJoy0Up		; then don't move up any more 
	inc	p0y
	inc	p0y
.endCheckJoy0Up
CheckJoy0Down
	lda	#%00100000
	bit	SWCHA
	bne	.endCheckJoy0Down
	lda	p0y
	cmp	#BOTTOM_LIMIT
	beq	.endCheckJoy0Down
	dec	p0y
	dec	p0y
.endCheckJoy0Down
CheckJoy0Left
	lda	#%01000000
	bit	SWCHA
	bne	.endCheckJoy0Left
	lda	#%00001000	; reflect the sprite
	sta	REFP0		; assume no reflection
	lda #1
	sta p0left
	jmp	.endCheckJoy0Right
.endCheckJoy0Left
CheckJoy0Right
    lda #%10000000
    bit SWCHA
	bne	.endCheckJoy0Right
	sta	REFP0
	lda #0
	sta p0left
.endCheckJoy0Right
;-----INPUT END-----

;-----REPLAY PHASE BEGIN-----
	lda idle ; check that idle = 0
	bne .endReplay

	lda phase ; check that phase = 0
	bne .endReplay

	lda #0
	sta gameover ; the game is not over if the code gets here

	lda hittimer   ; check that hittimer is 0
	bne .endReplay ; if still hitting, don't change anything

	lda breaktimer ; check that breaktimer is 0
	bne .endReplay ; if still breaking (little break between displays in case two consecutive of the same target)

	lda curr
	cmp level
	beq .phaseSwitch ; if reached end, switch the phase

	tax
	lda seq,x
	clc
	adc #1
	sta attempt ; current band to light up
	lda #1		; this basically simulates a player's hit
	sta hittimer
	lda #CORRECT_COLOR
	sta hitcolor

	inc curr
	
	jmp .endReplay
.phaseSwitch
	lda #1
	sta phase
	lda #0
	sta curr	 ; player needs to start from the beginning of the sequence	
.endReplay
;-----REPLAY PHASE END-----

;-----BREAK TIMER BEGIN-----
	lda idle
	bne .endCheckBreakTimer
CheckBreakTimer
	lda breaktimer
	beq .endCheckBreakTimer
	inc breaktimer
	lda breaktimer
	cmp #BREAK_DURATION
	bne .endCheckBreakTimer
	lda #0
	sta breaktimer

	; Move to next level or end the game after break if the level is over
	lda levelend
	beq .endCheckBreakTimer
	lda gameover
	bne .gameOver
.nextLevel
	inc level
	jmp .endNextLevelOrGameOver
.gameOver
	lda #1
	sta level
	jsr GenerateSequence ; new sequence is generated upon loss
.endNextLevelOrGameOver
	lda #0
	sta levelend
	sta phase
	sta curr
	sta attempt
.endCheckBreakTimer
;-----BREAK TIMER END-----

;-----COLLISION BEGIN-----
CheckCollisions
	lda #0
	; sta sound
checkCollisionM0P1
	lda CXM0P
	and #%10000000
	beq .noCollisionM0P1
	lda p1hit ; set if already handled collision, prevents running on multiple frames
	bne .endCollisionM0P1
	lda #0
	sta p0fire
	sta m0velocity

	lda m0band
	sta attempt ; attempted target
	
	lda #1
	sta hittimer
	sta p1hit ; Prevents duplicate collisions
	lda #0
	sta breaktimer

	ldx curr  	; current index
	lda seq,x 	; current value
	clc
	adc #1	  	; target = value + 1
	cmp attempt
	bne .wrong
.correct
	lda #CORRECT_COLOR
	sta hitcolor
	inc curr ; move to the next number in the sequence
	lda curr
	cmp level ; check if reached end of the level
	bne .endCollisionM0P1
	lda #1
	sta levelend

	jmp .endCollisionM0P1
.wrong
	lda #WRONG_COLOR
	sta hitcolor
	lda #1
	sta levelend
	sta gameover
	jmp .endCollisionM0P1
.noCollisionM0P1
	lda #0
	sta p1hit
.endCollisionM0P1
;-----COLLISION END-----

;-----MISSILE BEGIN-----
	lda p0fire
	beq .updateMissile0
	lda	p0y				; get player y-position
	sbc #3
	sta	m0y				; start the missile there
	lda	#%00000010
	sta	RESMP0			; release the missile from the P1 horizontal location
	; left or right fire
	lda p0left
	beq .right0
.left0
	lda	#%00110000 ; left-veocity
	jmp .apply0
.right0
	lda #%11010000 ; right-velocity
.apply0
	sta m0velocity

	lda	#0	
	sta p0fire
.updateMissile0
	lda m0velocity
	beq .stopMissile0
	lda	#%00000000
	sta	RESMP0
	lda m0velocity
	sta	HMM0			; store to move missile when HMOVE is strobed 
	jmp .endMissile0
.stopMissile0
	lda		#%00000010
	sta		RESMP0
	lda 	#0
	sta 	p0fire
	sta 	m0velocity
.endMissile0
;-----MISSILE END-----
	
.waitForVBlank
	lda	INTIM
	bne	.waitForVBlank
	sta	WSYNC
	sta	VBLANK
	sta HMOVE
	sta	CXCLR

;------------------------------------------------
; Kernel
;------------------------------------------------	
DrawScreen
;-----LEVEL DISPLAY BEGIN-----
	lda #HEADER_COLOR
	sta COLUBK
	sta WSYNC ; level display margin
	sta WSYNC
	ldy #LEVEL_DIGIT_HEIGHT
DrawLevel
	jsr DrawLevelSub
	sta WSYNC
	jsr DrawLevelSub
	dey
	sta WSYNC
	bpl DrawLevel

	lda #0
	sta PF1
	sta WSYNC ; level display margin
	sta WSYNC
	sta WSYNC
;-----LEVEL DISPLAY END-----
;-----FIELD DISPLAY BEGIN-----
	lda #FIELD_COLOR
	sta COLUBK
	lda	#FIELD_HEIGHT
	sta field
DrawField
;-----BAND DISPLAY BEGIN-----
	ldx #BAND_HEIGHT
DrawBand
;-----PLACE TARGET BEGIN-----
	cpx #BAND_HEIGHT
	beq .dontPlaceTarget
	lda band
	and #1
	beq .placeNow ; left-side places immediately,
	jsr WasteTime ; right-side wastes cycles to get a good spot
.placeNow	
	sta RESP1
	lda Target
	sta GRP1
	jmp .endPlaceTarget
.dontPlaceTarget ; Runs on first scanline of each band. Sets color for remaining band's target.
	lda attempt
	cmp band
	bne .ignoredTargetColor
.chosenTargetColor
	lda hittimer
	beq .ignoredTargetColor
	lda hitcolor
	jmp .endDontPlaceTarget
.ignoredTargetColor
	lda #BLACK
.endDontPlaceTarget
	sta COLUP1
	lda #0
	sta GRP1
.endPlaceTarget
;-----PLACE TARGET END-----

	lda p0gfx ; load what we stored previously for p0
	sta GRP0

	lda m0	  ; load what we stored previously for m0
	sta ENAM0

;-----PLAYER DISPLAY BEGIN-----
	lda p0y
	cmp field
	bne LoadPlayer
	lda #PLAYER_HEIGHT-1
	sta p0gfxIndex
LoadPlayer
	lda p0gfxIndex
	cmp	#$FF
	beq	NoPlayer
	tay
	lda	PlayerSprite,y
	sta	p0gfx
	dec p0gfxIndex
	jmp	EndPlayer
NoPlayer
	lda	#0
	sta	p0gfx
EndPlayer
;-----PLAYER DISPLAY END-----

;-----MISSILE DISPLAY BEGIN-----
	lda	#0			; missile off
	ldy	field
	cpy	m0y
	bne	.noMissile0
	lda band
	sta m0band
	lda	#%00000010	; missile on
.noMissile0
	sta	m0			; we'll use this in the kernel at the start of the next line.
;-----MISSILE DISPLAY END-----
	sta	WSYNC
	dec field
	dex
	bne	DrawBand
;-----BAND DISPLAY END-----
	dec band
	lda band
	bne DrawField
;-----FIELD DISPLAY END----
	lda #0 ; Extra Padding (two blank lines of background)
	sta GRP1
	sta WSYNC
	sta WSYNC

;------------------------------------------------
; Overscan
;------------------------------------------------
	lda	#%01000010
	sta	WSYNC
	sta	VBLANK
    lda	#36
    sta	TIM64T
.waitForOverscan
	lda INTIM
	bne .waitForOverscan
	jmp	MainLoop

;------------------------------------------------
; Subroutines
;------------------------------------------------
Rng
	lda seed		; this is the current random seed for the rng
	beq .eor		; if it's zero, EOR it with a value (accounts for 0)
	asl				; shift the bits left
	beq .skipEor 	; if the input is $80, skip the EOR
					; (needed because otherwise a seed of both $00 
					; and $80 will result in an output of $1d)
	bcc .skipEor		
.eor
	eor #$1d
.skipEor  
	sta seed		; put it back in the seed value
	inc seed		; Not strictly necessary, but testing resulted in increased "randomness" for this specific game
	rts				; back home

GenerateSequence
	ldx #SEQUENCE_SIZE	
.seqLoop
	jsr Rng		; generate random number
	lda seed	; get result of Rng
	and #$03	; use only lower two bits
	dex			; decrement x for next iteration
	sta seq,x	; store in sequence. after decrement so that is placed in correct offset (i.e. allows for offset 0)
	bne .seqLoop
	rts

DrawLevelSub
	lda (levelGfx),y
	sta PF1
	nop ; padding to let PF be drawn
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	lda #0 ; prevent second half from being drawn
	sta PF1
	rts

WasteTime
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	rts
	
;------------------------------------------------
; ROM Tables
;------------------------------------------------
; Player Sprite
PlayerSprite
	.byte	%11000000
	.byte	%11110000
	.byte	%11111100
	.byte	%11111111
	.byte	%11111111
	.byte	%11111100
	.byte	%11110000
	.byte	%11000000
Target
	.byte %11111111 ;
; Sound Table
SoundFreqs
	.byte #1
	.byte #2
	.byte #3
	.byte #4
; Level Digit Sprites
	align 256
Digits
Digit0
	.byte	%11100000
	.byte	%10100000
	.byte	%10100000
	.byte	%10100000
	.byte	%11100000
Digit1
	.byte	%00100000
	.byte	%00100000
	.byte	%00100000
	.byte	%00100000
	.byte	%00100000
Digit2
	.byte	%11100000
	.byte	%10000000
	.byte	%11100000
	.byte	%00100000
	.byte	%11100000
Digit3
	.byte	%11100000
	.byte	%00100000
	.byte	%11100000
	.byte	%00100000
	.byte	%11100000
Digit4
	.byte	%00100000
	.byte	%00100000
	.byte	%11100000
	.byte	%10100000
	.byte	%10100000
Digit5
	.byte	%11100000
	.byte	%00100000
	.byte	%11100000
	.byte	%10000000
	.byte	%11100000
Digit6
	.byte	%11100000
	.byte	%10100000
	.byte	%11100000
	.byte	%10000000
	.byte	%11100000
Digit7
	.byte	%00100000
	.byte	%00100000
	.byte	%00100000
	.byte	%00100000
	.byte	%11100000
Digit8
	.byte	%11100000
	.byte	%10100000
	.byte	%11100000
	.byte	%10100000
	.byte	%11100000
Digit9
	.byte	%00100000
	.byte	%00100000
	.byte	%11100000
	.byte	%10100000
	.byte	%11100000
Digit10
	.byte	%10111000
	.byte	%10101000
	.byte	%10101000
	.byte	%10101000
	.byte	%10111000
Digit11
	.byte	%10001000
	.byte	%10001000
	.byte	%10001000
	.byte	%10001000
	.byte	%10001000
Digit12
	.byte	%10111000
	.byte	%10100000
	.byte	%10111000
	.byte	%10001000
	.byte	%10111000
Digit13
	.byte	%10111000
	.byte	%10001000
	.byte	%10111000
	.byte	%10001000
	.byte	%10111000
Digit14
	.byte	%10001000
	.byte	%10001000
	.byte	%10111000
	.byte	%10101000
	.byte	%10101000
Digit15
	.byte	%10111000
	.byte	%10001000
	.byte	%10111000
	.byte	%10100000
	.byte	%10111000
Digit16
	.byte	%10111000
	.byte	%10101000
	.byte	%10111000
	.byte	%10100000
	.byte	%10111000
Digit17
	.byte	%10001000
	.byte	%10001000
	.byte	%10001000
	.byte	%10001000
	.byte	%10111000
Digit18
	.byte	%10111000
	.byte	%10101000
	.byte	%10111000
	.byte	%10101000
	.byte	%10111000
Digit19
	.byte	%10001000
	.byte	%10001000
	.byte	%10111000
	.byte	%10101000
	.byte	%10111000
DigitOffsets
	.byte 	<Digit0
	.byte 	<Digit1
	.byte 	<Digit2
	.byte 	<Digit3
	.byte 	<Digit4
	.byte 	<Digit5
	.byte 	<Digit6
	.byte 	<Digit7
	.byte 	<Digit8
	.byte 	<Digit9
	.byte 	<Digit10
	.byte 	<Digit11
	.byte 	<Digit12
	.byte 	<Digit13
	.byte 	<Digit14
	.byte 	<Digit15
	.byte 	<Digit16
	.byte 	<Digit17
	.byte 	<Digit18
	.byte 	<Digit19

;------------------------------------------------
; Interrupt Vectors
;------------------------------------------------
	echo [*-$F000]d, " ROM bytes used"
	ORG    $FFFA
	.word  Start         ; NMI
	.word  Start         ; RESET
	.word  Start         ; IRQ
    
	END