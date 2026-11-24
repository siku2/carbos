# filamancer

A Raspberry Pi 4B connected to a Profi3DMaker 3D printer from 3Dfactories over
USB.

## Printer board

The board is "3DF_Board_2v2" with an ATmega1281-16AU and a 16 MHz crystal. An FTDI FT232R connects USART1 (PD2/PD3) to USB at 115200 baud.

The board has no serial bootloader. DTR and RTS do not reset it. All flashing
goes over ISP.

### ISP header

The 2x10 header next to the MCU carries ISP. Column A is the row
closer to the MCU, column B the row closer to the board edge. Row 1 is the end
next to the 4-resistor array.

| Header | Signal    | MCU pin |
| ------ | --------- | ------- |
| A3     | RESET     | 20      |
| A4     | 5 V       |         |
| A5     | GND       |         |
| A6     | PDO (PE1) | 3       |
| B6     | PDI (PE0) | 2       |
| B7     | SCK (PB1) | 11      |


```sh
avrdude -c pickit_basic_isp -p m1281 -n -U signature:r:-:h
```

### Stock state

| Item      | Value                        |
| --------- | ---------------------------- |
| Signature | 1E 97 04                     |
| Fuses     | low F7, high 99, extended F7 |
| Lock bits | FF                           |
| EEPROM    | blank                        |

The fuses select the external crystal, leave JTAG and ISP enabled, disable
brown-out detection and start at address 0.

## Stock firmware

`pkgs/device-firmware/profi3dmaker` holds the flash image.
It is Sprinter 1.3.22T (kliment/Sprinter commit
3e6cce4) on a modified Arduino 0022/0023 core, ported to the ATmega1281 by
3Dfactories. Their changes include:

- Configuration and pin assignments.
- The M115 string `FIRMWARE_NAME: 3DFactories ... MACHINE_TYPE:EASY3DMAKER`.
  The build is still for the Profi3DMaker. The software endstops limit X, Y and
  Z to 400, 260 and 190 mm, while the Easy3DMaker is 200 x 200 x 230 mm.
- A tick on TIMER0_COMPA instead of the Arduino millis on TIMER0_OVF.
- An interrupt driven USART1 driver for the host link. USART0, which shares
  its pins with ISP, is switched off.

Sprinter is licensed GPLv3 or later. 3Dfactories did not publish the source of
this build.

### Pin map

| Function            | X     | Y     | Z        | E     |
| ------------------- | ----- | ----- | -------- | ----- |
| Step                | PA0   | PA1   | PA2      | PA3   |
| Direction           | PD0   | PD1   | PE2      | PB7   |
| Enable (active low) | PC0   | PC1   | PC2      | PC3   |
| Steps/mm            | 134.4 | 134.4 | 1055.959 | 204.3 |
| Travel (mm)         | 400   | 260   | 190      |       |

| Function          | Pin        | Notes                                   |
| ----------------- | ---------- | --------------------------------------- |
| X min endstop     | PG0        | low when triggered                      |
| Y max endstop     | PG1        | low when triggered                      |
| Z min endstop     | PG2        | low when triggered                      |
| Hotend heater     | PE4        |                                         |
| Bed heater        | PE3        |                                         |
| Part fan          | PB5        |                                         |
| Heater LED        | PB4        | follows the hotend heater               |
| Board fan         | PB6        | on while a driver is enabled, plus 60 s |
| Hotend thermistor | PF0 (ADC0) | 100k Epcos, Sprinter table 6            |
| Bed thermistor    | PF2 (ADC2) | 100k Epcos, Sprinter table 6            |

The firmware does not enable the internal pull-ups on the endstops. All
direction pins are low for moves towards the minimum.
