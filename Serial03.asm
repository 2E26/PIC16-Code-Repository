; Serial03.asm
;
; A basic program to read and echo bytes entered into the serial monitor. Is
; functionally equivalent to Serial02, but uses USART.asm library to call
; serial commands
; Based on the MPASM assembler

	LIST	    P=16F877A
	#include    <P16F877A.inc>
	#include    "USART.asm"
	
	__CONFIG _CP_OFF & _WDT_OFF & _PWRTE_ON & _XT_OSC
	
	CBLOCK 0x20

	ENDC
	
	ORG 0x0000
	GOTO START
	
	ORG 0x0004
	RETFIE
	
START:
	CALL	    USART_Init
	MOVLW	    'S'
	CALL	    USART_SendByte
	MOVLW	    'e'
	CALL	    USART_SendByte
	MOVLW	    'r'
	CALL	    USART_SendByte
	MOVLW	    'i'
	CALL	    USART_SendByte
	MOVLW	    'a'
	CALL	    USART_SendByte
	MOVLW	    'l'
	CALL	    USART_SendByte
	MOVLW	    ' '
	CALL	    USART_SendByte
	MOVLW	    'r'
	CALL	    USART_SendByte
	MOVLW	    'e'
	CALL	    USART_SendByte
	MOVLW	    'a'
	CALL	    USART_SendByte
	MOVLW	    'd'
	CALL	    USART_SendByte
	MOVLW	    'y'
	CALL	    USART_SendByte
	CALL	    USART_SendCRLF
    
LOOP:
	CALL	    USART_GetByte
	CALL	    USART_SendByte
	GOTO	    LOOP
	
	END
