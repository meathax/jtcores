# JTMOO FPGA core Compatible with Konami's Wild West C.O.W.-Boys of Moo Mesa hardware

By Jose Tejada (@topapate)

You can show your appreciation through
* [Patreon](https://patreon.com/jotego)
* [Paypal](https://paypal.me/topapate)
* [Github](https://github.com/sponsors/jotego)

Project source code hosted at http://www.github.com/jotego/jtcores
License: GPL3, you are obligued to publish your code if you use mine

Yes, you always wanted to have an arcade board at home. First you couldn't get it because your parents somehow did not understand you. Then you grow up and your wife doesn't understand you either. Don't worry, JT cores are here to the rescue.

I hope you will have as much fun with this project as I had while working on it!

# Supported Systems

This FPGA core is compatible with the following arcade PCB:

- Wild West C.O.W.-Boys of Moo Mesa (`moomesa`, `moomesauac`, `moomesauab`, `moomesaaab`)

Bucky O'Hare and known bootlegs are excluded. Due to limitations in the internal
RAM memory of small FPGA devices, this core does not run on MiST/SiDi FPGAs.

# Game Configuration

This game does not use DIP switches but a small EEPROM to save the configuration.
Access the configuration by pressing F2 on your keyboard or pressing button 1 and
coin in on the Analogue Pocket. Follow the game menu to alter the configuration
from that point on. A valid default EEPROM is required for a normal boot.

# Known differences from MAME

- Plane 2 (`CI3`) is one colour bit narrower than MAME's model: the board trace shows `DSB4` unwired into the K053251 (`M9` pin 64, NC).
- IRQ level assignment follows the real 74LS148 priority encoder (5 = DMA-end edge, 4 = K053252 `INT1`, 3 = K053990 `/IPL0`), unlike MAME's own IRQ4/IRQ5 gating in `moo.cpp`.
- The K054539 mixes the YM2151 (aux) signal internally, per traced board nets; MAME's driver models no aux input at all.

# PLD Equations

Decoded PAL fusemaps: [`pal/moomesa/`](pal/moomesa/) — `055373` (main) and `054744` (sound) address decoders.

# Credits

- meathax
- Furrtek: [SiliconRE](https://github.com/furrtek/SiliconRE) custom chip research
- R. Belmont, Acho A. Tang and the [MAME](https://github.com/mamedev/mame) contributors
