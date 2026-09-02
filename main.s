        AREA finalproject, CODE, READONLY
        EXPORT __main

; LCD control lines on GPIOA
RS      EQU 0x20        ; PA5
RW      EQU 0x40        ; PA6
EN      EQU 0x80        ; PA7

__main  PROC

        ; clocks first, nothing works without these
        LDR     R0, =0x40023830          ; AHB1ENR
        LDR     R1, [R0]
        ORR     R1, R1, #0x01            ; GPIOA
        ORR     R1, R1, #0x02            ; GPIOB
        ORR     R1, R1, #0x04            ; GPIOC
        STR     R1, [R0]

        LDR     R0, =0x40023840          ; APB1ENR
        LDR     R1, [R0]
        ORR     R1, R1, #0x01            ; TIM2
        ORR     R1, R1, #(1 << 17)       ; USART2
        STR     R1, [R0]

        LDR     R0, =0x40023844          ; APB2ENR, ADC lives here not APB1
        LDR     R1, [R0]
        ORR     R1, R1, #(1 << 8)        ; ADC1
        STR     R1, [R0]

        LTORG

        ; GPIOA
        ; PA0 AF (TIM2 pwm), PA1 analog (pot), PA2 AF (uart tx), PA5-7 output (lcd ctrl)
        LDR     R0, =0x40020000

        LDR     R2, =0xA8000000          ; reset value, keeps the SWD pins alone
        LDR     R3, =0x0000FFFF          ; can't BIC this as an immediate, has to go through a reg
        BIC     R2, R2, R3

        ORR     R2, R2, #(0x2 << 0)      ; PA0
        ORR     R2, R2, #(0x3 << 2)      ; PA1
        ORR     R2, R2, #(0x2 << 4)      ; PA2
        ORR     R2, R2, #(0x1 << 10)     ; PA5
        ORR     R2, R2, #(0x1 << 12)     ; PA6
        ORR     R2, R2, #(0x1 << 14)     ; PA7
        STR     R2, [R0, #0x00]

        ; AFRL: PA0 -> AF1 (TIM2_CH1), PA2 -> AF7 (USART2)
        LDR     R2, [R0, #0x20]
        BIC     R2, R2, #0x0000000F
        ORR     R2, R2, #0x00000001
        BIC     R2, R2, #0x00000F00
        ORR     R2, R2, #0x00000700
        STR     R2, [R0, #0x20]

        ; GPIOB - PB0-3 LEDs out, PB5 switch in
        LDR     R0, =0x40020400

        LDR     R2, [R0, #0x00]
        LDR     R3, =0x00000FFF
        BIC     R2, R2, R3
        ORR     R2, R2, #0x00000055
        STR     R2, [R0, #0x00]

        ; pull-up on PB5 so it idles high, switch pulls it to gnd
        LDR     R2, [R0, #0x0C]
        BIC     R2, R2, #(0x3 << 10)
        ORR     R2, R2, #(0x1 << 10)
        STR     R2, [R0, #0x0C]

        ; LEDs off to start
        LDR     R2, =0x000F0000
        STR     R2, [R0, #0x18]

        ; GPIOC - PC0-7 is the LCD data bus
        LDR     R0, =0x40020800
        LDR     R2, =0x00015555
        STR     R2, [R0, #0x00]

        LTORG

        ; TIM2 pwm setup
        ; 84MHz / 84 = 1MHz tick, ARR 1000 -> 1kHz pwm
        LDR     R8, =0x40000000          ; keep TIM2 base in R8 the whole time

        LDR     R1, =83
        STR     R1, [R8, #0x28]          ; PSC
        LDR     R1, =1000
        STR     R1, [R8, #0x2C]          ; ARR
        MOV     R1, #0
        STR     R1, [R8, #0x34]          ; CCR1 = duty
        LDR     R1, =0x0068
        STR     R1, [R8, #0x18]          ; CCMR1, pwm mode 1
        MOV     R1, #1
        STR     R1, [R8, #0x20]          ; CCER, ch1 out on
        MOV     R1, #1
        STR     R1, [R8, #0x14]          ; EGR, force update
        LDR     R1, [R8, #0x00]
        ORR     R1, R1, #0x81
        STR     R1, [R8, #0x00]          ; CR1, go

        ; ADC1 ch1 on PA1
        LDR     R9, =0x40012000          ; ADC base stays in R9

        LDR     R1, [R9, #0x10]
        BIC     R1, R1, #(0x7 << 3)
        ORR     R1, R1, #(0x7 << 3)      ; slowest sample time, pot is noisy
        STR     R1, [R9, #0x10]

        LDR     R1, [R9, #0x08]
        ORR     R1, R1, #1               ; ADON
        STR     R1, [R9, #0x08]

        BL      USART2_Init

        LTORG

        ; LCD boot text
        BL      LCDInit

        MOV     R2, #0x80
        BL      LCDCommand

        MOV     R3, #'P'
        BL      LCDData
        MOV     R3, #'W'
        BL      LCDData
        MOV     R3, #'R'
        BL      LCDData
        MOV     R3, #':'
        BL      LCDData
        MOV     R3, #' '
        BL      LCDData
        MOV     R3, #'0'
        BL      LCDData
        MOV     R3, #'0'
        BL      LCDData
        MOV     R3, #'0'
        BL      LCDData
        MOV     R3, #'%'
        BL      LCDData

        MOV     R11, #0                  ; mode: 0 bright, 1 count
        BL      LCDShowMode

        MOV     R10, #255                ; last shown %, 255 so first pass always updates

main_loop
        BL      CheckButton
        BL      ReadADC_Avg8             ; -> R4

        ; pwm value 0-1000
        LSR     R5, R4, #2
        CMP     R5, #1000
        IT      HI
        MOVHI   R5, #1000

        ; percent
        MOV     R1, #100
        MUL     R7, R4, R1
        LDR     R1, =4095
        UDIV    R7, R7, R1

        ; snap to 0/25/50/75/100, cutoffs are the midpoints
        CMP     R7, #13
        BLT     pct_0
        CMP     R7, #38
        BLT     pct_25
        CMP     R7, #63
        BLT     pct_50
        CMP     R7, #88
        BLT     pct_75
        B       pct_100

pct_0
        MOV     R7, #0
        B       pct_done
pct_25
        MOV     R7, #25
        B       pct_done
pct_50
        MOV     R7, #50
        B       pct_done
pct_75
        MOV     R7, #75
        B       pct_done
pct_100
        MOV     R7, #100

pct_done
        CMP     R11, #0
        BEQ     do_bright_mode

do_count_mode
        MOV     R1, #0
        STR     R1, [R8, #0x34]          ; pwm off
        BL      UpdateLEDBar
        B       after_mode_action

do_bright_mode
        STR     R5, [R8, #0x34]
        BL      LEDsOff

after_mode_action
        ; only redraw when the number actually changes, otherwise the lcd flickers
        CMP     R7, R10
        BEQ     no_lcd_update
        MOV     R10, R7
        BL      LCDShowPercent
        BL      UARTShowStatus

no_lcd_update
        BL      SmallDelay
        B       main_loop
        ENDP

        LTORG

; USART2, 9600 8N1
; board is on the 16MHz HSI not 84MHz, took a while to figure that out
; 16000000/9600 = 1667 = 0x683
USART2_Init PROC
        PUSH    {R0-R1, LR}
        LDR     R0, =0x40004400
        LDR     R1, =0x0683
        STR     R1, [R0, #0x08]          ; BRR
        LDR     R1, =((1 << 13) :OR: (1 << 3))   ; UE + TE
        STR     R1, [R0, #0x0C]          ; CR1
        POP     {R0-R1, LR}
        BX      LR
        ENDP

; send R3 out the uart, wait for TXE first
UARTSendChar PROC
        PUSH    {R0-R1, LR}
        LDR     R0, =0x40004400
uart_tx_wait
        LDR     R1, [R0, #0x00]
        TST     R1, #(1 << 7)
        BEQ     uart_tx_wait
        STR     R3, [R0, #0x04]
        POP     {R0-R1, LR}
        BX      LR
        ENDP

; not used anymore, left in case
UARTNewLine PROC
        PUSH    {R3, LR}
        MOV     R3, #13
        BL      UARTSendChar
        MOV     R3, #10
        BL      UARTSendChar
        POP     {R3, LR}
        BX      LR
        ENDP

; prints "MODE: xxx PWR: xxx%" to teraterm
; ends with just \r so it rewrites the same line instead of scrolling
UARTShowStatus PROC
        PUSH    {R0-R3, R7, R11, LR}

        MOV     R3, #'M'
        BL      UARTSendChar
        MOV     R3, #'O'
        BL      UARTSendChar
        MOV     R3, #'D'
        BL      UARTSendChar
        MOV     R3, #'E'
        BL      UARTSendChar
        MOV     R3, #':'
        BL      UARTSendChar
        MOV     R3, #' '
        BL      UARTSendChar

        CMP     R11, #0
        BEQ     uart_mode_bright

uart_mode_count
        MOV     R3, #'C'
        BL      UARTSendChar
        MOV     R3, #'O'
        BL      UARTSendChar
        MOV     R3, #'U'
        BL      UARTSendChar
        MOV     R3, #'N'
        BL      UARTSendChar
        MOV     R3, #'T'
        BL      UARTSendChar
        B       uart_after_mode

uart_mode_bright
        MOV     R3, #'B'
        BL      UARTSendChar
        MOV     R3, #'R'
        BL      UARTSendChar
        MOV     R3, #'I'
        BL      UARTSendChar
        MOV     R3, #'G'
        BL      UARTSendChar
        MOV     R3, #'H'
        BL      UARTSendChar
        MOV     R3, #'T'
        BL      UARTSendChar

uart_after_mode
        MOV     R3, #' '
        BL      UARTSendChar
        MOV     R3, #'P'
        BL      UARTSendChar
        MOV     R3, #'W'
        BL      UARTSendChar
        MOV     R3, #'R'
        BL      UARTSendChar
        MOV     R3, #':'
        BL      UARTSendChar
        MOV     R3, #' '
        BL      UARTSendChar

        CMP     R7, #0
        BEQ     uart_000
        CMP     R7, #25
        BEQ     uart_025
        CMP     R7, #50
        BEQ     uart_050
        CMP     R7, #75
        BEQ     uart_075

uart_100
        MOV     R3, #'1'
        BL      UARTSendChar
        MOV     R3, #'0'
        BL      UARTSendChar
        MOV     R3, #'0'
        BL      UARTSendChar
        B       uart_pct_done

uart_000
        MOV     R3, #'0'
        BL      UARTSendChar
        MOV     R3, #'0'
        BL      UARTSendChar
        MOV     R3, #'0'
        BL      UARTSendChar
        B       uart_pct_done

uart_025
        MOV     R3, #'0'
        BL      UARTSendChar
        MOV     R3, #'2'
        BL      UARTSendChar
        MOV     R3, #'5'
        BL      UARTSendChar
        B       uart_pct_done

uart_050
        MOV     R3, #'0'
        BL      UARTSendChar
        MOV     R3, #'5'
        BL      UARTSendChar
        MOV     R3, #'0'
        BL      UARTSendChar
        B       uart_pct_done

uart_075
        MOV     R3, #'0'
        BL      UARTSendChar
        MOV     R3, #'7'
        BL      UARTSendChar
        MOV     R3, #'5'
        BL      UARTSendChar

uart_pct_done
        MOV     R3, #'%'
        BL      UARTSendChar
        MOV     R3, #13                  ; \r only, no \n
        BL      UARTSendChar

        POP     {R0-R3, R7, R11, LR}
        BX      LR
        ENDP

; PB5 high = bright, low = count
; only touches the lcd if the mode actually flipped
CheckButton PROC
        PUSH    {R0-R2, LR}
        LDR     R0, =0x40020400
        LDR     R1, [R0, #0x10]          ; IDR
        TST     R1, #(1 << 5)
        BNE     btn_is_bright
btn_is_count
        MOV     R2, #1
        B       btn_check
btn_is_bright
        MOV     R2, #0
btn_check
        CMP     R2, R11
        BEQ     btn_done
        MOV     R11, R2
        BL      LCDShowMode
btn_done
        POP     {R0-R2, LR}
        BX      LR
        ENDP

; one conversion, result in R4
ReadADC1_CH1 PROC
        MOV     R1, #1
        STR     R1, [R9, #0x34]          ; SQR3 ch1
        LDR     R1, [R9, #0x08]
        ORR     R1, R1, #(1 << 30)       ; SWSTART
        STR     R1, [R9, #0x08]
adc_wait
        LDR     R1, [R9, #0x00]
        TST     R1, #(1 << 1)            ; EOC
        BEQ     adc_wait
        LDR     R4, [R9, #0x4C]
        BX      LR
        ENDP

; 8 samples averaged, raw pot readings were way too jumpy
ReadADC_Avg8 PROC
        PUSH    {R5-R7, LR}
        MOV     R6, #0
        MOV     R7, #8
avg_loop
        BL      ReadADC1_CH1
        ADD     R6, R6, R4
        SUBS    R7, R7, #1
        BNE     avg_loop
        LSR     R4, R6, #3               ; /8
        POP     {R5-R7, LR}
        BX      LR
        ENDP

LEDsOff PROC
        PUSH    {R0-R1, LR}
        LDR     R0, =0x40020400
        LDR     R1, =0x000F0000          ; BSRR reset PB0-3
        STR     R1, [R0, #0x18]
        POP     {R0-R1, LR}
        BX      LR
        ENDP

; LED bar from R7
; using BSRR so set + clear happen in one write, upper half clears lower half sets
UpdateLEDBar PROC
        PUSH    {R0-R2, R7, LR}
        LDR     R0, =0x40020400

        CMP     R7, #25
        BEQ     led_25
        CMP     R7, #50
        BEQ     led_50
        CMP     R7, #75
        BEQ     led_75
        CMP     R7, #100
        BEQ     led_100

        LDR     R2, =0x000F0000          ; 0%
        B       led_store
led_25
        LDR     R2, =0x000E0001
        B       led_store
led_50
        LDR     R2, =0x000C0003
        B       led_store
led_75
        LDR     R2, =0x00080007
        B       led_store
led_100
        LDR     R2, =0x0000000F

led_store
        STR     R2, [R0, #0x18]
        POP     {R0-R2, R7, LR}
        BX      LR
        ENDP

; rewrite the 3 digits after "PWR: "
LCDShowPercent PROC
        PUSH    {R7, LR}

        MOV     R2, #0x85                ; line 1 pos 5
        BL      LCDCommand

        CMP     R7, #0
        BEQ     show_000
        CMP     R7, #25
        BEQ     show_025
        CMP     R7, #50
        BEQ     show_050
        CMP     R7, #75
        BEQ     show_075

show_100
        MOV     R3, #'1'
        BL      LCDData
        MOV     R3, #'0'
        BL      LCDData
        MOV     R3, #'0'
        BL      LCDData
        B       lcd_done

show_000
        MOV     R3, #'0'
        BL      LCDData
        MOV     R3, #'0'
        BL      LCDData
        MOV     R3, #'0'
        BL      LCDData
        B       lcd_done

show_025
        MOV     R3, #'0'
        BL      LCDData
        MOV     R3, #'2'
        BL      LCDData
        MOV     R3, #'5'
        BL      LCDData
        B       lcd_done

show_050
        MOV     R3, #'0'
        BL      LCDData
        MOV     R3, #'5'
        BL      LCDData
        MOV     R3, #'0'
        BL      LCDData
        B       lcd_done

show_075
        MOV     R3, #'0'
        BL      LCDData
        MOV     R3, #'7'
        BL      LCDData
        MOV     R3, #'5'
        BL      LCDData

lcd_done
        POP     {R7, LR}
        BX      LR
        ENDP

; line 2 mode text
LCDShowMode PROC
        PUSH    {R11, LR}

        MOV     R2, #0xC0                ; line 2
        BL      LCDCommand

        MOV     R3, #'M'
        BL      LCDData
        MOV     R3, #'O'
        BL      LCDData
        MOV     R3, #'D'
        BL      LCDData
        MOV     R3, #'E'
        BL      LCDData
        MOV     R3, #':'
        BL      LCDData
        MOV     R3, #' '
        BL      LCDData

        CMP     R11, #0
        BEQ     mode_bright

mode_count
        MOV     R3, #'C'
        BL      LCDData
        MOV     R3, #'O'
        BL      LCDData
        MOV     R3, #'U'
        BL      LCDData
        MOV     R3, #'N'
        BL      LCDData
        MOV     R3, #'T'
        BL      LCDData
        MOV     R3, #' '                 ; pad so the T from BRIGHT gets wiped
        BL      LCDData
        MOV     R3, #' '
        BL      LCDData
        B       mode_done

mode_bright
        MOV     R3, #'B'
        BL      LCDData
        MOV     R3, #'R'
        BL      LCDData
        MOV     R3, #'I'
        BL      LCDData
        MOV     R3, #'G'
        BL      LCDData
        MOV     R3, #'H'
        BL      LCDData
        MOV     R3, #'T'
        BL      LCDData
        MOV     R3, #' '
        BL      LCDData

mode_done
        POP     {R11, LR}
        BX      LR
        ENDP

        LTORG

; standard hd44780 init, order matters
LCDInit PROC
        PUSH    {LR}
        BL      delay
        MOV     R2, #0x38                ; 8 bit, 2 lines
        BL      LCDCommand
        MOV     R2, #0x0E                ; display on
        BL      LCDCommand
        MOV     R2, #0x01                ; clear
        BL      LCDCommand
        MOV     R2, #0x06                ; cursor moves right
        BL      LCDCommand
        POP     {LR}
        BX      LR
        ENDP

; command in R2. data on PC0-7, pulse EN on PA7
; had to push R0-R3 here, STRB + only saving R2 was corrupting stuff
LCDCommand PROC
        PUSH    {R0-R3, LR}
        LDR     R0, =0x40020000          ; A
        LDR     R1, =0x40020800          ; C
        STR     R2, [R1, #0x14]
        MOV     R2, #EN
        STR     R2, [R0, #0x14]
        BL      delay
        MOV     R2, #0
        STR     R2, [R0, #0x14]          ; latches on the falling edge
        POP     {R0-R3, LR}
        BX      LR
        ENDP

; same thing but RS high, char in R3
LCDData PROC
        PUSH    {R0-R3, LR}
        LDR     R0, =0x40020000
        LDR     R1, =0x40020800
        STR     R3, [R1, #0x14]
        MOV     R2, #(RS :OR: EN)
        STR     R2, [R0, #0x14]
        BL      delay
        MOV     R2, #RS
        STR     R2, [R0, #0x14]
        POP     {R0-R3, LR}
        BX      LR
        ENDP

; busy wait. R4/R5 have to be saved here, this was the bug that broke the adc for a while
delay   PROC
        PUSH    {R4, R5, LR}
        MOV     R5, #50
loop1
        MOV     R4, #0xFF
loop2
        SUBS    R4, R4, #1
        BNE     loop2
        SUBS    R5, R5, #1
        BNE     loop1
        POP     {R4, R5, LR}
        BX      LR
        ENDP

SmallDelay PROC
        PUSH    {R4, R5, LR}
        MOV     R5, #10
sloop1
        MOV     R4, #0xFF
sloop2
        SUBS    R4, R4, #1
        BNE     sloop2
        SUBS    R5, R5, #1
        BNE     sloop1
        POP     {R4, R5, LR}
        BX      LR
        ENDP

        LTORG
        END
