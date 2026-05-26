; USART.asm
;
; A library file of serial functions for the PIC16F877A
; Useful for communicating with a PC by way of the serial port

USART_Init:
;-------------------------------------------------------------------------------
; Init: - initializes serial communications with the hardware USART. Assumes
;	a 4 MHz oscillator input, 9600 baud, asynchronous communication, and
;	BRGH = 1
; Inputs: none
; Destroys: W
; Outputs: none, processor is in memory bank 0
;-------------------------------------------------------------------------------
	BSF	    0x03, 5		    ; select bank 1
	BCF	    0x03, 6
	MOVLW	    D'25'		    ; set transmission rate to 9600 baud
	MOVWF	    0x99		    ; load into SPBRG
	MOVLW	    B'00100100'		    ; set xmit status to enabled, with
	MOVWF	    0x98		    ; BRGH speed set to high
	BCF	    0x87, 6		    ; RC6 is an output pin
	BSF	    0x87, 7		    ; RC7 is an input pin
	BCF	    0x83, 5		    ; select bank 0
	BCF	    0x83, 6
	MOVLW	    B'10010000'		    ; set rcv status to port enable,
	MOVWF	    0X18		    ; receive enable.
	RETURN
	
USART_GetByte:
;-------------------------------------------------------------------------------
; GetByte: - wait until a character is received, store it in W
; Inputs: none
; Destroys: W
; Outputs: W - received byte
;-------------------------------------------------------------------------------
USART_WAITRX:
	CALL	    USART_OERRCheck
	BTFSS	    0x0C, 5		    ; check if byte is ready to read
	GOTO	    USART_WAITRX	    ; if not, keep checking until so
	MOVF	    0x1A, W		    ; save the byte in W
	RETURN
	
USART_CheckGetByte:
;-------------------------------------------------------------------------------
; CheckGetByte: - same as GetByte, but does not delay program if a byte is not
;		ready. Uses the Carry flag to indicate if a Byte was read.
; Inputs: none
; Destroys: W, Carry Flag
; Outputs: W - received byte. Carry Flag - 1 if received byte, 0 if not
;-------------------------------------------------------------------------------
	CALL	    USART_OERRCheck
	BCF	    0x03, 0		    ; clear carry flag
	BTFSS	    0x0C, 5		    ; check if byte is ready to read
	RETURN				    ; if not, return
	MOVF	    0x1A, W		    ; if so, read it into W
	BSF	    0x03, 0		    ; set carry flag
	RETURN				    ; return if a byte is read or not

USART_SendByte:
;-------------------------------------------------------------------------------
; SendByte: - wait until transmitter is ready, sends byte stored in W
; Inputs: USART must be initialized. W - byte to send via serial port.
; Destroys: none
; Outputs: none
;-------------------------------------------------------------------------------
USART_WAITTX:
	BTFSS	    0x0C, 4		    ; check if byte is done being sent
	GOTO	    USART_WAITTX	    ; if not, keep checking until so
	MOVWF	    0x19		    ; send the byte in W
	RETURN	
	
USART_OERRCheck:
;-------------------------------------------------------------------------------
; OERRCheck: - checks if the OERR flag is set. If so, clears it by toggling
;		the CREN bit in RXSTA
; Inputs: none
; Alters: RXSTA
; Outputs: none
;-------------------------------------------------------------------------------
	BTFSS	    0x18, 1		    ; check if OERR bit is set
	RETURN				    ; if not, return
	BCF	    0x18, 4		    ; CREN = 0
	BSF	    0x18, 4		    ; CREN = 1
	RETURN				    ; return

USART_SendCR:
;-------------------------------------------------------------------------------
; SendCR: - sends carriage return character 0x0D
; Inputs: none
; Destroys: W
; Outputs: none
;-------------------------------------------------------------------------------
	MOVLW	   0x0D
	CALL	   USART_SendByte
	RETURN
	
USART_SendLF:
;-------------------------------------------------------------------------------
; SendLF: - sends line feed character 0x0A
; Inputs: none
; Destroys: W
; Outputs: none
;-------------------------------------------------------------------------------
	MOVLW	   0x0A
	CALL	   USART_SendByte
	RETURN
	
USART_SendCRLF:
;-------------------------------------------------------------------------------
; SendCRLF: - sends carriage return and line feed characters 0x0D0A
; Inputs: none
; Destroys: W
; Outputs: none
;-------------------------------------------------------------------------------
	MOVLW	   0x0D
	CALL	   USART_SendByte
	MOVLW	   0x0A
	CALL	   USART_SendByte
	RETURN
	
USART_PrintBytetoChar:
;-------------------------------------------------------------------------------
; PrintBytetoChar: - prints W to the serial terminal as a hex value (00-FF)
; Memory: Temp, Temp2
; Inputs: W holds numerical value to be printed 
; Destroys: W
; Outputs: none
;-------------------------------------------------------------------------------    
	MOVWF		Temp		; save W in a temporary byte
	SWAPF		Temp, W		; write the same byte back to W with nibbles reversed
	ANDLW		0x0F		; strike off top four bits
	MOVWF		Temp2
	SUBLW		0x09		; subtract W from 9
	BTFSS		STATUS, 0	; check if carry flag is set. If so, W <= 9
	GOTO		Letter		; 
Number:	MOVF		Temp2, 0	; restore original nibble
	ADDLW		0x30		; add 30h to convert numerical digit to ASCII character (0-9)
	GOTO		CharPt		;
Letter: MOVF		Temp2, 0	; restore original nibble
	ADDLW		0x37		; add 37h to convert numerical digit to ASCII character (A-F)
CharPt: CALL		USART_SendByte	; send the high character to the serial port
	MOVF		Temp, 0		; get the original value of W back in original order
	ANDLW		0x0F		; strip off four bits
	MOVWF		Temp2		; save nibble
	SUBLW		0x09		; W = 9 - W
	BTFSS		STATUS, 0	; if result <= 0 then handle numerical digit
	GOTO		Ltr2		; 
Num2:	MOVF		Temp2, 0	; restore original nibble
	ADDLW		0x30		; add 30h to convert to ASCII
	GOTO		ChrPt2		;
Ltr2:	MOVF		Temp2, 0	; restore original nibble
	ADDLW		0x37		; add 37h to convert to ASCII
ChrPt2:	CALL		USART_SendByte	; print low character to serial port
	RETURN
