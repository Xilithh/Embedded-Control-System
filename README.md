# Embedded Control System — STM32F401RE in ARM Assembly

Bare-metal ARM assembly on an STM32F401RE Nucleo board. A potentiometer is sampled through the on-chip ADC and drives two output modes — PWM LED brightness or a four-LED bar graph — while a 16×2 HD44780 LCD shows the live power percentage and USART2 streams it to a serial terminal.

Built as the final project for Microcontroller Architecture at Texas A&M (Apr–May 2026).

> **About this repo:** this is an archive of the finished project. All development was done in **Keil MDK (µVision) with ARMCLANG v6.24**; the Keil project files are not included, so `main.s` is the complete source. See [Building it yourself](#building-it-yourself) to recreate the project.

<!-- TODO: add a photo or short GIF of the board running here. -->

## What it does

| Mode | Behavior |
|---|---|
| **BRIGHT** | Potentiometer position sets the duty cycle of a PWM output (TIM2, PA0) driving an LED — brightness tracks the knob continuously. |
| **COUNT** | Potentiometer position maps to a four-level bar graph on PB0–PB3, written atomically through `BSRR`. |

In both modes the LCD shows the current power percentage and the same value is written to USART2 at 9600 baud, overwriting a single terminal line using a bare carriage return so the reading updates in place. A switch on PB5 toggles between modes.

## Hardware

- STM32F401RE Nucleo-64
- 10 kΩ potentiometer (ADC input)
- 16×2 HD44780 character LCD, 8-bit parallel interface
- 4× LEDs + current-limiting resistors (bar graph), 1× LED (PWM)
- Toggle/push switch (mode select)
- Breadboard, jumpers; USB to the on-board ST-Link for power, flashing, and the USART2 virtual COM port

<!-- TODO: verify every pin below against main.s before publishing. -->

| Signal | MCU pin | Notes |
|---|---|---|
| Potentiometer wiper | ADC1 input | see `main.s` for channel |
| PWM LED | PA0 | TIM2 CH1 |
| Bar-graph LEDs | PB0–PB3 | PB0 is on CN8 pin 4 (Arduino A3), not CN10 |
| Mode switch | PB5 | |
| LCD data (D0–D7) | GPIOC | 8-bit parallel |
| LCD control (RS / E) | GPIOA | |
| Serial out | USART2 (PA2) | routed to ST-Link VCP, 9600 8N1 |

## Building it yourself

1. Open Keil µVision and create a new project targeting **STM32F401RETx** (Nucleo-F401RE). Select the ARM Compiler 6 toolchain.
2. Add `main.s` to the source group. No C runtime or HAL is used.
3. Build, then flash over the Nucleo's ST-Link.
4. Open a serial terminal (TeraTerm, PuTTY, `screen`) on the ST-Link COM port at **9600 baud, 8N1**. If the line doesn't overwrite cleanly, set the terminal to treat CR as CR only (no implicit LF).

## Engineering notes

Things that went wrong and how they were fixed — kept here because they're the useful part of the project.

- **Register corruption from delay routines.** `delay` / `SmallDelay` clobbered R4/R5 without saving them, corrupting caller state in ways that only showed up several instructions later. Fixed with `PUSH`/`POP` around every call-clobbered register; the LCD `LCDCommand` / `LCDData` routines were widened to `PUSH {R0-R3}` for the same reason.
- **Partial writes to GPIO ODR.** `STRB` to the output data register corrupted neighboring pins. Replaced with full 32-bit `STR` writes (and `BSRR` for the bar graph, which sets and clears atomically).
- **Deprecated conditional moves.** ARMCLANG rejected `MOVEQ` / `MOVNE` in this context; replaced with explicit compare-and-branch logic.
- **MODER configuration.** Setting GPIOA mode bits with immediate constants tripped encoding limits; mode bits are now set pin-by-pin by loading a mask into a register and clearing with `BIC` before `ORR`.
- **USART2 baud rate.** Running on the 16 MHz HSI with no PLL, the BRR value for 9600 baud was determined empirically as `0x0683` after the calculated value produced garbage.
- **ADC noise.** The raw ADC reading jittered at the LSBs, causing the bar graph to flicker at level boundaries. Fixed by averaging multiple samples before mapping to a level.
- **Wrong header for PB0.** The bar graph's lowest LED did nothing until PB0 was traced to CN8 pin 4 (A3) rather than the CN10 header.

## Files

- `main.s` — complete program: clock/GPIO/ADC/TIM2/USART2 setup, main loop, LCD driver, mode logic.
