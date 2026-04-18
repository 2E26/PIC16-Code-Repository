; Serial02.asm
;
; A second set of code for serial communications between PIC and PC.
; This one will echo characters input from the keyboard

    LIST	    P=16F877A
    #include	    <P16F877A.inc>

    __CONFIG _CP_OFF & _WDT_OFF & _PWRTE_ON & _XT_OSC

    CBLOCK 0x20
	RXBYTE
    ENDC
    
    ORG		    0x0000	    ; reset vector points to START
    GOTO	    START
    
    ORG		    0x0004	    ; interrupt return - not sure this is solid
    RETFIE
    
START:
    ; initialize the UART
    BSF		    0x03, 5	    ; select bank 1
    MOVLW	    D'25'	    ; set transmission rate to 9600 baud
    MOVWF	    0x99	    ; load into SPBRG
    MOVLW	    B'00100100'	    ; set transmit status to enabled, with
    MOVWF	    0x98	    ; BRGH speed set to high
    BCF		    0x87, 6	    ; RC6 is an output pin
    BSF		    0x87, 7	    ; RC7 is an input pin
    BCF		    0x83, 5	    ; select bank 0
    MOVLW	    B'10010000'	    ; set receive stats to serial port enable,
    MOVWF	    0X18	    ; receive enable.
    
LOOP:
    CALL	    GETCHAR
    CALL	    PUTCHAR
    MOVWF	    RXBYTE
    GOTO	    LOOP
    
;-----------------------------------------------------------------------------
; GETCHAR - wait until a character is received, store it in W
GETCHAR:
WAITRX:
    BTFSS	    0x0C, 5
    GOTO	    WAITRX
    MOVF	    0x1A, W
    RETURN
    
;-----------------------------------------------------------------------------
; PUTCHAR - wait until no character is being sent, send byte from W to serial
PUTCHAR:
WAITTX:
    BTFSS	    0x0C, 4
    GOTO	    WAITTX
    MOVWF	    0x19
    RETURN

    END