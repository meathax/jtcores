# JTMOO FPGA core Compatible with Konami's Moo Mesa hardware

By Jose Tejada (@topapate)

You can show your appreciation through
* [Patreon](https://patreon.com/jotego)
* [Paypal](https://paypal.me/topapate)
* [Github](https://github.com/sponsors/jotego)

Project source code hosted at http://www.github.com/jotego/jtcores
License: GPL3, you are obligued to publish your code if you use mine

# Supported Systems

This FPGA core is compatible with the following arcade PCBs:

- Wild West C.O.W.-Boys of Moo Mesa

MiST and SiDi builds are skipped because of the BRAM budget.

# Game Configuration

This game does not use DIP switches but a small EEPROM to save the
configuration. Access the configuration by pressing F2 on your keyboard,
or by pressing button 1 and coin in the Analogue Pocket. Follow the game
menu to alter the configuration from that point on.

# PLD Equations

Decoded fusemaps for the 055373 (main address decoder) and 054744 (sound
address decoder) are in the [pal](pal/moomesa) folder.

# Credits

- Jorge Cwik: [fx68k](https://github.com/ijor/fx68k)
- Daniel Wallner, Sorgelig and the T80 contributors
- Furrtek: [SiliconRE](https://github.com/furrtek/SiliconRE) custom chip research
- Caius: 054744 PAL dump
- [MAME](https://github.com/mamedev/mame) contributors
