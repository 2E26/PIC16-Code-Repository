; Serial01.asm
;
; A simple test of serial data transmission from PIC to PC
; We will start with a routine to send data once every
; second or so via the UART port on the built-in support
;
; Program flow:
;
; 1. initialize the PIC for serial transmission
;
; 2. send the character 'S' over serial
;
; 3. delay one second-ish
;
; 4. repeat forever

PROCESSOR 16F877A
#include <xc.inc>

CONFIG FOSC = XT
CONFIG WDTE = OFF
CONFIG PWRTE = ON
CONFIG CP = OFF

GLOBAL _main
GLOBAL start_initialization

PSECT udata_bank0
D1:	DS 1
D2:	DS 1
D3:	DS 1
    
PSECT code,class=CODE,delta=2

start_initialization:
	GOTO _main
    
_main:
    ; here we initialize the registers needed to establish serial transmission
    ; we are going for 9600 baud, which means the Baud Rate Generator Register
    ; (SPBRG) to equal 25 when the TXSTA mode is set to high speed and the
    ; crystal oscillator is 4.00 MHz.
	BSF	0x03, 5		    ; choose RAM bank 1
	MOVLW	25		    ; baud rate 9600
	MOVWF	0x99		    ; load into SPBRG
	MOVLW	0b00100100	    ; set TXEN and BRGH to high speed
	MOVWF	0x98		    ; load into TXSTA
	CLRF	0x88		    ; set port D to output
	BCF	0x83, 5		    ; back to RAM bank 0
	MOVLW	0b10000000	    ; set serial port enable
	MOVWF	0x18		    ; load into RCSTA
	MOVLW	0x7F		    ; set up a pattern for a rotating LED display
	MOVWF	0x08		    ; load it into PORTD
	BSF	0x03, 0		    ; also set carry flag
    
Loop:	
	CALL	WaitTX		    ; wait until ready to send a byte
	MOVLW	0x53		    ; load 'S' into W register
	MOVWF	0x19		    ; load byte into TXREG to be transmit
	CALL	WaitTX		    ; wait until ready to send
	MOVLW	0x0A		    ; load new line into W register
	MOVWF	0x19		    ; transmit
	RRF	0x08, 1	    ; move the LED to form a visual indication
	
Delay:	MOVLW	50		    ; delay routine
	MOVWF	D1		    ; nested loops
Del1:	MOVLW	50		    ; 100 * 100 * 50 = 500,000
	MOVWF	D2
Del2:	MOVLW	50
	MOVWF	D3
Del3:	NOP
	DECFSZ	D3, F
	GOTO	Del3
	DECFSZ	D2, F
	GOTO	Del2
	DECFSZ	D1, F
	GOTO	Del1
	GOTO	Loop
	
WaitTX:
	BTFSS	0x0C, 4
	GOTO	WaitTX
	RETURN
