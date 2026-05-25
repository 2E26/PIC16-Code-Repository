; EEPROM01.asm
;
; The first in a series of programs to load 6502 assembly code into ROM memory using a PIC16 MCU
; Loads a fixed set of machine code instructions into ROM starting at 7E00h as well as the
; reset and interrupt vectors at 7FFAh - 7FFFh.
;
; Note that ROM memory is 8000h less than actual computer memory, as current ROM occupies the upper
; 32K of memory available to the 6502.
;
; Based on the MPASM assembler

        LIST			P=16F877A
        #include                <P16F877A.inc>
	
        __CONFIG _CP_OFF & _WDT_OFF & _PWRTE_ON & _XT_OSC & _LVP_OFF

        CBLOCK 0x20
                D1
                D2
                D3
                Databyte
		AddressL
		AddressH
		Temp
		Temp2
		MsgIndex
		DataIndex
		Writesuccess
        ENDC

        ORG 0x0000
        GOTO START

        ORG 0x0004
        RETFIE
	
	#include		"USART.asm"

; Program flow:
;
; 1) initialize USART, initialize GPIO registers, and wait for a key
; 2) display a prompt 
; 3) load program into the EEPROM one byte at a time
; 4) increment address and write another byte
; 5) once all bytes have been written, read all bytes and ensure they match
; 6) loop forever when all bytes have been written
;
; File Register use
;
; PORTA(0): address bit A14
; PORTA(1): Write Enable
; PORTA(2): Chip Enable
; PORTA(3): Output Enable
; PORTB: address bits A0 - A7
; PORTC(0-5): A8-A13
; PORTD: data bus bits D0-D7

START:
        BCF		STATUS, RP1 ; set memory bank 1
        BSF		STATUS, RP0
	MOVLW		0x00
	MOVWF		TRISB	    ; set PortB to output
	MOVWF		TRISD	    ; set PortD to output
	MOVLW		0x80	    ; set PortC to output except RC7
	MOVWF		TRISC	    ; configure PORTC
	MOVLW		0x00	    ; set PortA to output
	MOVWF		TRISA	    ; configure PortA
	MOVLW		0x06	    ; configure ADCON1
	MOVWF		ADCON1	    ; all A/D ports are digital ports
	BCF		STATUS, 6   ; set memory bank 0
	BCF		STATUS, 5
	BSF		PORTA, 1    ; set control bits /WE, /CE, /OE
	BSF		PORTA, 2    ; to initial states
	BCF		PORTA, 3
	
	; now, write the following program to EEPROM starting at 0x7E00
	; which will show up in computer memory 0xFE00
	; 0xA9018D0002A9058D0102A9088D02024C00FE
	;
	; start:
	; LDA	#$01
	; STA	$0200
	; LDA	#$05
	; STA	$0201
	; LDA	#$08
	; STA	$0202
	; JMP	start
	
        CALL		USART_Init
	CALL		Delay
	CALL		EEPROM_StartMessage
	CALL		USART_GetByte
	MOVLW		0x00	    ; set starting address to 0x7E00
	MOVWF		AddressL
	MOVLW		0x7E	    ; which will be 0xFE00 in computer
	MOVWF		AddressH    ; addressing
	CALL		EEPROM_SetAddress
	
	CLRF		DataIndex   ; Data Index = 0
	
LoadLoop:
    
	; this routine reads a byte from a repository of program data and places
	; it on the EEPROM chip. It then writes a message stating what byte was
	; written to what address on the chip. 
    
	MOVF		DataIndex, W	    ; W = Data Index
	CALL		EEPROM_LoadData	    ; get a byte from the list
	MOVWF		Databyte
	CALL		EEPROM_WriteByte    ; write it to the EEPROM
	CALL		EEPROM_WriteMessage ; place text in the serial port
	MOVF		Databyte, W	    ; W = Databyte
	CALL		PrintBytetoChar	    ; print ASCII version of W
	CALL		EEPROM_WriteMsg2    ; place text in the serial port
	MOVF		AddressH, W	    ; W = high address byte
	CALL		PrintBytetoChar	    ; print ASCII address high
	MOVF		AddressL, W	    ; W = low address byte
	CALL		PrintBytetoChar	    ; print ASCII address low
	CALL		USART_SendCRLF	    ; send 0x0D0A to serial port
	CALL		EEPROM_IncrementAddress
	INCF		DataIndex, F	    ; Data Index ++
	MOVF		DataIndex, W
	XORLW		0x12		    ; Is W > 17?
	BTFSC		STATUS, 2		    ; If zero flag is set...
	GOTO		VectorLoad	    ; go to next part of loop
	GOTO		LoadLoop	    ; go back to do it again
	
VectorLoad:
	CLRF		DataIndex
	MOVLW		0xFA
	MOVWF		AddressL
	MOVLW		0x7F
	MOVWF		AddressH
	CALL		EEPROM_SetAddress
	
VectorLoop:
	MOVF		DataIndex, 0	    ; W = Data Index
	CALL		EEPROM_Vectors	    ; get a byte from the list
	MOVWF		Databyte
	CALL		EEPROM_WriteByte    ; write it to the EEPROM
	CALL		EEPROM_WriteMessage ; place text in the serial port
	MOVF		Databyte, 0	    ; W = Databyte
	CALL		PrintBytetoChar	    ; print ASCII version of W
	CALL		EEPROM_WriteMsg2    ; place text in the serial port
	MOVF		AddressH, 0	    ; W = high address byte
	CALL		PrintBytetoChar	    ; print ASCII address high
	MOVF		AddressL, 0	    ; W = low address byte
	CALL		PrintBytetoChar	    ; print ASCII address low
	CALL		USART_SendCRLF	    ; send 0x0D0A to serial port
	CALL		EEPROM_IncrementAddress
	INCF		DataIndex, F	    ; Data Index ++
	MOVF		DataIndex, 0
	XORLW		0x06		    ; Is W > 5?
	BTFSC		STATUS, 2	    ; If zero flag is set...
	GOTO		VerifyCode	    ; go to next part of loop
	GOTO		VectorLoop	    ; go back to do it again
	
VerifyCode:
	CALL		Delay		    ; give hardware a chance to catch up
	CLRF		PORTD
	CLRF		DataIndex	    ; set data reading counter to zero	
	MOVLW		0x00		    ; set address to the beginning
	MOVWF		Writesuccess	    ; clear successful write counter
	MOVWF		AddressL
	MOVLW		0x7E
	MOVWF		AddressH
	CALL		EEPROM_SetAddress
	BCF		STATUS, 6	    ; set PORTD to input
	BSF		STATUS, 5	    ; TRISD is in bank 1
	MOVLW		0xFF		    ; all eight bits of D are input
	MOVWF		TRISD
	BCF		STATUS, 6	    ; return to bank 0
	BCF		STATUS, 5
VerifyLoop:
	CALL		EEPROM_ReadByte	    ; Read an EEPROM byte into W	
	MOVWF		Databyte	    ; save to memory
	CALL		EEPROM_ReadMessage  ; print the message stating we got
	MOVF		Databyte, W	    ; a byte from the EEPROM
	CALL		PrintBytetoChar	    ; at the designated address
	CALL		EEPROM_ReadMessage2 
	MOVF		AddressH, W
	CALL		PrintBytetoChar
	MOVF		AddressL, W
	CALL		PrintBytetoChar
	CALL		USART_SendCRLF
	MOVF		DataIndex, W
	CALL		EEPROM_LoadData
	XORWF		Databyte, W
	BTFSC		STATUS, 2
	INCF		Writesuccess, F
	CALL		EEPROM_IncrementAddress
	INCF		DataIndex, F
	MOVF		DataIndex, W
	XORLW		0x12
	BTFSC		STATUS, 2
	GOTO		VectorVerify
	GOTO		VerifyLoop
	
VectorVerify:
	CALL		Delay
	CLRF		DataIndex
	MOVLW		0xFA
	MOVWF		AddressL
	MOVLW		0x7F
	MOVWF		AddressH
	CALL		EEPROM_SetAddress
VectorVerifyLoop:
	CALL		EEPROM_ReadByte	    ; Read an EEPROM byte into W	
	MOVWF		Databyte	    ; save to memory
	CALL		EEPROM_ReadMessage  ; print the message stating we got
	MOVF		Databyte, 0	    ; a byte from the EEPROM
	CALL		PrintBytetoChar	    ; at the designated address
	CALL		EEPROM_ReadMessage2 
	MOVF		AddressH, 0
	CALL		PrintBytetoChar
	MOVF		AddressL, 0
	CALL		PrintBytetoChar
	CALL		USART_SendCRLF
	MOVF		DataIndex, W
	CALL		EEPROM_Vectors
	XORWF		Databyte, W
	BTFSC		STATUS, 2
	INCF		Writesuccess, F
	CALL		EEPROM_IncrementAddress
	INCF		DataIndex, F
	MOVF		DataIndex, W
	XORLW		0x06
	BTFSC		STATUS, 2
	GOTO		EEPROM_DoneMessage
	GOTO		VectorVerifyLoop

EEPROM_DoneMessage:
        CLRF		MsgIndex
	MOVLW		0x03
	MOVWF		PCLATH
EEPROM_DoneMsgLoop:
	MOVF		MsgIndex, W
	CALL		EEPROM_DoneMsg
	XORLW		0x00
	BTFSC		STATUS, 2
	GOTO		EEPROM_Done
	CALL		USART_SendByte
	INCF		MsgIndex, F
	GOTO		EEPROM_DoneMsgLoop
EEPROM_Done:
	MOVF		Writesuccess, W    
	CALL		PrintBytetoChar
	CALL		USART_SendCRLF
	CALL		USART_SendCRLF
LOOP:
	BSF		PORTA, 1        ; set control bits /WE, /CE, /OE
	BSF		PORTA, 2        ; to a safe point before shutting down 
	BSF		PORTA, 3
	SLEEP
	GOTO		LOOP

Delay:	MOVLW		50		; delay routine
	MOVWF		D1	        ; nested loops
Del1:	MOVLW		50		; 50 * 50 * 8 = 20,000
	MOVWF		D2
Del2:	MOVLW		8
	MOVWF		D3
Del3:	NOP
	DECFSZ		D3, F
	GOTO		Del3
	DECFSZ		D2, F
	GOTO		Del2
	DECFSZ		D1, F
	GOTO		Del1
	RETURN
	
PrintBytetoChar:
	MOVWF		Temp		; save W in a temporary byte
	SWAPF		Temp, 0		; write the same byte back to W with nibbles reversed
	ANDLW		0x0F		; strike off top four bits
	MOVWF		Temp2
	SUBLW		0X09		; subtract 9
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
	BTFSS		STATUS, 0	; if result < 0 then handle numerical digit
	GOTO		Ltr2		; 
Num2:	MOVF		Temp2, 0	; restore original nibble
	ADDLW		0x30		; add 30h to convert to ASCII
	GOTO		ChrPt2		;
Ltr2:	MOVF		Temp2, 0	; restore original nibble
	ADDLW		0x37		; add 37h to convert to ASCII
ChrPt2:	CALL		USART_SendByte	; print low character to serial port
	RETURN
		
EEPROM_SetAddress:
	BCF		STATUS, 5	; select bank 0
	BCF		STATUS, 6
	MOVF		AddressL, 0	; grab the low byte of address stored in memory
	MOVWF		PORTB		; store it in PORTB
	MOVF		PORTC, 0	; store PORTC in W
	ANDLW		0xC0		; clear out all but the two high bits
	MOVWF		Temp		; and store it in memory
	MOVF		AddressH, 0	; grab the high byte of address stored in memory
	ANDLW		0x3F		; mask out the two highest bits
	IORWF		Temp, 0		; restore the two high bits originally in PORTC
	MOVWF		PORTC		; write the address to PORTC 0-5, preserving TX/RX bits
	BSF		PORTA, 0	; make RA0 = 1
	BTFSS		AddressH, 6	; if bit is supposed to be 0
	BCF		PORTA, 0	; then make RA0 = 0
	RETURN

EEPROM_IncrementAddress:
	INCFSZ		AddressL, 1
	GOTO		NoOverflowL
	INCFSZ		AddressH, 1
	GOTO		NoOverflowL
	GOTO		OverflowH
NoOverflowL:
	CALL		EEPROM_SetAddress
	RETURN
OverflowH:
	GOTO		OverflowH	; for now, just loop forever if broken

EEPROM_WriteByte:
	CALL		Delay
	MOVF		Databyte, W	; take the data to be written
	MOVWF		PORTD		; write it to port D
	BCF		PORTA, 2	; /CE low
	BSF		PORTA, 3	; /OE high
	NOP
	NOP
	BCF		PORTA, 1	; /WE low
	NOP
	NOP
	BSF		PORTA, 1	; /WE high
	NOP
	NOP
	BSF		PORTA, 2	; /CE high
	BCF		PORTA, 3	; /OE low
	RETURN
	
EEPROM_ReadByte:
	CALL		Delay
	BSF		PORTA, 1	; ensure /WE is high
	BCF		PORTA, 2	; make /CE low (chip enable)
	BCF		PORTA, 3	; make /OE low (enable read)
	NOP
	NOP
	MOVF		PORTD, W	; get the byte read at PORTD into W
	NOP
	NOP
	BSF		PORTA, 3	; make /OE high again
	NOP
	BSF		PORTA, 2	; make /CE high again
	RETURN
	
EEPROM_StartMessage:
        CLRF		MsgIndex
	MOVLW		0x03
	MOVWF		PCLATH
EEPROM_StartMsgLoop:
	MOVF		MsgIndex, W
	CALL		EEPROM_StartMsgStrt
	XORLW		0x00
	BTFSC		STATUS, 2
	RETURN
	CALL		USART_SendByte
	INCF		MsgIndex, F
	GOTO		EEPROM_StartMsgLoop

EEPROM_WriteMessage:
        CLRF		MsgIndex
	MOVLW		0x03
	MOVWF		PCLATH
EEPROM_WriteMsgLoop:
	MOVF		MsgIndex, W
	CALL		EEPROM_WriteMsgStrt
	XORLW		0x00
	BTFSC		STATUS, 2
	RETURN
	CALL		USART_SendByte
	INCF		MsgIndex, F
	GOTO		EEPROM_WriteMsgLoop	

EEPROM_WriteMsg2:
        CLRF		MsgIndex		; message index = 0
	MOVLW		0x03
	MOVWF		PCLATH
EEPROM_WriteMsg2Loop:
	MOVF		MsgIndex, W		; W = message index
	CALL		EEPROM_WriteMsg2Strt	; grab character Msg2[indx]
	XORLW		0x00			; is Msg2[indx] == 0x00?
    	BTFSC		STATUS, 2		; if Z flag set, then exit
	RETURN
	CALL		USART_SendByte		; otherwise, send byte
	INCF		MsgIndex, F		; message index += 1
	GOTO		EEPROM_WriteMsg2Loop	; repeat routine
	
EEPROM_ReadMessage:
        CLRF		MsgIndex
	MOVLW		0x03
	MOVWF		PCLATH
EEPROM_ReadMsgLoop:
	MOVF		MsgIndex, W
	CALL		EEPROM_ReadMsgStrt
	XORLW		0x00
	BTFSC		STATUS, 2
	RETURN
	CALL		USART_SendByte
	INCF		MsgIndex, F
	GOTO		EEPROM_ReadMsgLoop	

EEPROM_ReadMessage2:
        CLRF		MsgIndex
	MOVLW		0x03
	MOVWF		PCLATH
EEPROM_ReadMsg2Loop:
	MOVF		MsgIndex, W
	CALL		EEPROM_ReadMsg2Strt
	XORLW		0x00
	BTFSC		STATUS, 2
	RETURN
	CALL		USART_SendByte
	INCF		MsgIndex, F
	GOTO		EEPROM_ReadMsg2Loop	

; All messages and code are stored at the beginning of a new page in program
; memory. That way, the code to add to the PCL avoids and overflow that 
	
   ORG	0x0300					; used to prevent page overflow

EEPROM_StartMsgStrt:
	ADDWF		PCL, F			; 0x0300
        RETLW           'P'			; 0x0301
        RETLW           'r'			; 0x0302
        RETLW           'e'			; 0x0303
        RETLW           's'			; 0x0304
        RETLW           's'			; 0x0305    
        RETLW           ' '			; 0x0306
        RETLW           'a'			; 0x0307
        RETLW           ' '			; 0x0308
        RETLW           'k'			; 0x0309
        RETLW           'e'			; 0x030A
        RETLW		'y'			; 0x030B
        RETLW           ' '			; 0x030C
        RETLW           't'			; 0x030D
        RETLW           'o'			; 0x030E
        RETLW           ' '			; 0x030F
        RETLW           'l'			; 0x0310
        RETLW           'o'			; 0x0311
        RETLW           'a'			; 0x0312
        RETLW           'd'			; 0x0313
        RETLW           ' '			; 0x0314
        RETLW           'E'			; 0x0315
        RETLW           'E'			; 0x0316
        RETLW           'P'			; 0x0317
        RETLW           'R'			; 0x0318
        RETLW           'O'			; 0x0319
        RETLW           'M'			; 0x031A
        RETLW           '.'			; 0x031B
	RETLW		0x0D			; 0x031C
	RETLW		0x0A			; 0x031D
	RETLW		0x00			; 0x031E
	
EEPROM_WriteMsgStrt:
	ADDWF		PCL, F			; 0x031F
        RETLW           'W'			; 0x0320
	RETLW           'r'			; 0x0321
        RETLW           'o'			; 0x0322
        RETLW           't'			; 0x0323
        RETLW           'e'			; 0x0324
        RETLW           ' '			; 0x0325
        RETLW           'b'			; 0x0326
        RETLW           'y'			; 0x0327
        RETLW           't'			; 0x0328
        RETLW           'e'			; 0x0329
        RETLW           ' '			; 0x032A
	RETLW		0x00			; 0x032B
	
EEPROM_WriteMsg2Strt:
	ADDWF		PCL, F			; 0x032C
        RETLW           ' '			; 0x032D
        RETLW           't'			; 0x032E
        RETLW           'o'			; 0x032F
        RETLW           ' '			; 0x0330
        RETLW           'a'			; 0x0331
        RETLW           'd'			; 0x0332
        RETLW           'd'			; 0x0333
        RETLW           'r'			; 0x0334
        RETLW           'e'			; 0x0335
        RETLW           's'			; 0x0336
        RETLW           's'			; 0x0337
	RETLW		' '			; 0x0338
	RETLW		'0'			; 0x0339
	RETLW		'x'			; 0x033A
	RETLW		0x00			; 0x033B
	
EEPROM_ReadMsgStrt:
	ADDWF		PCL, F			; 0x033C
	RETLW           'R'			; 0x033D
        RETLW           'e'			; 0x033E
        RETLW           'a'			; 0x033F
        RETLW           'd'			; 0x0340
        RETLW           ' '			; 0x0341
        RETLW           'b'			; 0x0342
        RETLW           'y'			; 0x0343
        RETLW           't'			; 0x0344
        RETLW           'e'			; 0x0345
        RETLW           ' '			; 0x0346
	RETLW		0x00			; 0x0347

EEPROM_ReadMsg2Strt:
	ADDWF		PCL, F			; 0x0348
	RETLW           ' '			; 0x0349
        RETLW           'f'			; 0x034A
        RETLW           'r'			; 0x034B
        RETLW           'o'			; 0x034C
        RETLW           'm'			; 0x034D
        RETLW           ' '			; 0x034E
        RETLW           'E'			; 0x034F
        RETLW           'E'			; 0x0350
        RETLW           'P'			; 0x0351
        RETLW           'R'			; 0x0352
	RETLW           'O'			; 0x0353
        RETLW           'M'			; 0x0354
        RETLW           ' '			; 0x0355
        RETLW           'a'			; 0x0356
        RETLW           'd'			; 0x0357
        RETLW           'd'			; 0x0358
        RETLW           'r'			; 0x0359
        RETLW           'e'			; 0x035A
        RETLW           's'			; 0x035B
        RETLW           's'			; 0x035C
        RETLW           ' '			; 0x035D
	RETLW		'0'			; 0x035E
	RETLW		'x'			; 0x035F
	RETLW		0x00			; 0x0360
	
EEPROM_LoadData:
	ADDWF		PCL, F		; add W to the program counter	0x0361
	RETLW		0xA9		; 0xFE00    LDA			0x0362
	RETLW		0x01		; 0xFE01    #$01		0x0363
	RETLW		0x8D		; 0xFE02    STA			0x0364
	RETLW		0x00		; 0xFE03    $00			0x0365
	RETLW		0x02		; 0xFE04    $02			0x0366
	RETLW		0xA9		; 0xFE05    LDA			0x0367
	RETLW		0x05		; 0xFE06    #$05		0x0368
	RETLW		0x8D		; 0xFE07    STA			0x0369
	RETLW		0x01		; 0xFE08    $01			0x036A
	RETLW		0x02		; 0xFE09    $02			0x036B
	RETLW		0xA9		; 0xFE0A    LDA			0x036C
	RETLW		0x08		; 0xFE0B    #$08		0x036D
	RETLW		0x8D		; 0xFE0C    STA			0x036E
	RETLW		0x02		; 0xFE0D    $02			0x036F	
	RETLW		0x02		; 0xFE0E    $02			0x0370
	RETLW		0x4C		; 0xFE0F    JMP			0x0371
	RETLW		0x00		; 0xFE10    $00			0x0372
	RETLW		0xFE		; 0xFE11    $FE			0x0373
	
EEPROM_Vectors:
	ADDWF		PCL, F		;				0x0374
	RETLW		0x00		; 0xFFFA			0x0375
	RETLW		0xFE		; 0xFFFB			0x0376
	RETLW		0x00		; 0xFFFC			0x0377
	RETLW		0xFE		; 0xFFFD			0x0378
	RETLW		0x00		; 0xFFFE			0x0379
	RETLW		0xFE		; 0xFFFF			0x037A
	
EEPROM_DoneMsg:
	ADDWF		PCL, F
	RETLW		'O'		; 0x037B
	RETLW		'p'		; 0x037C
	RETLW		'e'		; 0x037D
	RETLW		'r'		; 0x037E
	RETLW		'a'		; 0x037F
	RETLW		't'		; 0x0380
	RETLW		'i'		; 0x0381
	RETLW		'o'		; 0x0382
	RETLW		'n'		; 0x0383
	RETLW		' '		; 0X0384
	RETLW		'c'		; 0x0385
	RETLW		'o'		; 0x0386
	RETLW		'm'		; 0x0387
	RETLW		'p'		; 0x0388
	RETLW		'l'		; 0x0389
	RETLW		'e'		; 0x038A
	RETLW		't'		; 0x038B
	RETLW		'e'		; 0x038C
	RETLW		'.'		; 0x038D
	RETLW		' '		; 0x038E
	RETLW		'B'		; 0x038F
	RETLW		'y'		; 0x0390
	RETLW		't'		; 0x0391
	RETLW		'e'		; 0x0392
	RETLW		's'		; 0x0393
	RETLW		' '		; 0x0394
	RETLW		'w'		; 0x0395
	RETLW		'r'		; 0x0396
	RETLW		'i'		; 0x0397
	RETLW		't'		; 0x0398
	RETLW		't'		; 0x0399
	RETLW		'e'		; 0x039A
	RETLW		'n'		; 0x039B
	RETLW		':'		; 0x039C
	RETLW		' '		; 0x039D
	RETLW		0x00		; 0x039E
	
	END
