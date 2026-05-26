; EEPROM0A.asm
;
; A program to test basic read/write functions on an EEPROM AT28C256. Written
; because I'm having trouble doing just that in a more useful program
; Based on the MPASM assembler
	
; pin map for PIC16F877A to AT28C256
;
; PORTA(0) - A14
; PORTA(1) - /WE
; PORTA(2) - /CE
; PORTA(3) - /OE
; PORTB(0-7) - A0-A7
; PORTC(0-5) - A8-A13
; PORTC(6-7) - USART TX/RX
; PORTD(0-7) - D0-D7

	LIST	    P=16F877A
	#include    <P16F877A.inc>
	
	__CONFIG _CP_OFF & _WDT_OFF & _PWRTE_ON & _XT_OSC & _LVP_OFF
	
	CBLOCK 0x20
	    D1
	    D2
	    D3
	    Temp
	    Temp2
	    AddressL
	    AddressH
	    OutCount
	ENDC
	
	ORG 0x0000
	GOTO START
	
	ORG 0x0004
	RETFIE
	
	#include    "EEPROM.asm"
	#include    "USART.asm"
	
START:
	BCF	    STATUS, RP1			; set memory bank 1
	BSF	    STATUS, RP0
	CLRF	    TRISA			; PORTA as output
	CLRF	    TRISB			; PORTB as output
	MOVLW	    0x80
	MOVWF	    TRISC			; PORTC as output except RC7
	MOVLW	    0xFF
	MOVWF	    TRISD			; PORTD as input
	MOVLW	    0x06
	MOVWF	    ADCON1			; all I/O pins digital
	BCF	    STATUS, RP0			; set memory bank 0    
	CALL	    USART_Init			; 9600 baud, BRGH = 1
	MOVLW	    0x05			; program delay for 5 mS
	MOVWF	    D1				; load file register for delay
	CALL	    EEPROM_msDelay		; call delay
	BSF	    PORTA, 1			; /WE high
	BSF	    PORTA, 2			; /CE high
	BSF	    PORTA, 3			; /OE high
	CLRF	    AddressL
	CLRF	    AddressH
	CALL	    EEPROM_SetAddress		; set address to 0x0000
	CALL	    USART_GetByte		; wait for key press to start
	
ReadLoop01:
	CLRF	    OutCount
	MOVF	    AddressH, W			; print the address on the start
	CALL	    USART_PrintBytetoChar	; of the line
	MOVF	    AddressL, W
	CALL	    USART_PrintBytetoChar
	MOVLW	    ':'
	CALL	    USART_SendByte
	MOVLW	    ' '
	CALL	    USART_SendByte
ReadLoop02:
	CALL	    EEPROM_ReadByte		; read a value from the EEPROM
	CALL	    USART_PrintBytetoChar	; display it on the terminal
	MOVLW	    ' '
	CALL	    USART_SendByte
	CALL	    EEPROM_IncrementAddress	; move up one address
	MOVF	    AddressH, W			; get high address
	XORLW	    0x80			; are we at the end of EEPROM?
	BTFSC	    STATUS, 2			; check for a match
	GOTO	    LOOP			; exit program if so
	INCF	    OutCount
	BTFSS	    OutCount, 4			; is OutCount 16?
	GOTO	    ReadLoop02			; if not, read EEPROM again
	CALL	    USART_SendCRLF		; if so, begin new line
	GOTO	    ReadLoop01
    
LOOP:
	BSF	    PORTA, 1
	BSF	    PORTA, 2
	BSF	    PORTA, 3
	SLEEP
	GOTO	    LOOP
    
	END
